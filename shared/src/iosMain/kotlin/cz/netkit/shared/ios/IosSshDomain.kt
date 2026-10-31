package cz.netkit.shared.ios

import cz.netkit.shared.json.JSON_MAX_DEPTH
import cz.netkit.shared.json.jsonNestingDepth
import cz.netkit.shared.ssh.*
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

enum class IosSshDataFailure { SIZE, UTF8, FORMAT, SCHEMA, INVALID_DATA, CONFLICT }
data class IosSshDataResult(val data: SshData?, val failure: IosSshDataFailure?)
data class IosSshImportResult(val imported: SshProfileImport?, val failure: SshProfileImportFailure?)
data class IosSshPlanResult(val plan: SshImportPlan?, val failure: SshProfileImportFailure?)
data class IosSshImportApplyResult(val data: SshData?, val failure: SshProfileImportFailure?)

/** Synchronous value operations. Swift serializes metadata transactions and writes atomically. */
class IosSshDomain {
    private val json = Json { encodeDefaults = true }
    fun emptyData(): SshData = SshData()

    fun profile(id: String, name: String, host: String, port: Int, username: String,
        authentication: SshAuthentication, secretRef: String?, keyRef: String?, startupCommand: String,
        keepaliveSeconds: Int): SshProfile? = SshProfile(id, name, host, port, username, authentication,
            secretRef, keyRef, startupCommand, keepaliveSeconds).takeIf { it.valid() }

    fun decodeData(bytes: ByteArray): IosSshDataResult {
        if (bytes.size > 1_048_576) return invalid(IosSshDataFailure.SIZE)
        val text = try { bytes.decodeToString(throwOnInvalidSequence = true) }
            catch (_: CharacterCodingException) { return invalid(IosSshDataFailure.UTF8) }
        if (jsonNestingDepth(text) > JSON_MAX_DEPTH) return invalid(IosSshDataFailure.FORMAT)
        return try {
            val root = json.parseToJsonElement(text) as? JsonObject ?: return invalid(IosSshDataFailure.FORMAT)
            val schema = (root["schema"] as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull
            if (schema != 1) invalid(IosSshDataFailure.SCHEMA)
            else checked(json.decodeFromString(SshData.serializer(), text))
        } catch (_: SerializationException) { invalid(IosSshDataFailure.FORMAT) }
        catch (_: IllegalArgumentException) { invalid(IosSshDataFailure.FORMAT) }
    }

    fun encodeData(data: SshData): ByteArray? = if (!data.valid()) null else
        json.encodeToString(SshData.serializer(), data).encodeToByteArray().takeIf { it.size <= 1_048_576 }

    fun upsertProfile(data: SshData, profile: SshProfile): IosSshDataResult {
        if (!data.valid() || !profile.valid()) return invalid(IosSshDataFailure.INVALID_DATA)
        val previous = data.profiles.firstOrNull { it.id == profile.id }
        val targetChanged = previous != null && (previous.host != profile.host || previous.port != profile.port || previous.username != profile.username)
        val saved = if (targetChanged) profile.copy(secretRef = null) else profile
        val updated = if (previous == null) data.profiles + saved else data.profiles.map { if (it.id == profile.id) saved else it }
        return checked(data.copy(profiles = updated))
    }

    fun upsertKey(data: SshData, key: SshKeyInfo): IosSshDataResult {
        if (!data.valid()) return invalid(IosSshDataFailure.INVALID_DATA)
        val updated = if (data.keys.none { it.id == key.id }) data.keys + key else data.keys.map { if (it.id == key.id) key else it }
        return checked(data.copy(keys = updated))
    }

    fun hostDecision(data: SshData, offered: TrustedHostKey): HostKeyDecision =
        hostKeyDecision(data.hostKeys.firstOrNull { it.endpoint == offered.endpoint }, offered)

    /** Unknown-host confirmation cannot replace a different saved key, including a racing insertion. */
    fun trustUnknown(data: SshData, offered: TrustedHostKey): IosSshDataResult {
        if (!data.valid()) return invalid(IosSshDataFailure.INVALID_DATA)
        val previous = data.hostKeys.firstOrNull { it.endpoint == offered.endpoint }
        if (previous != null && previous != offered) return invalid(IosSshDataFailure.CONFLICT)
        return checked(if (previous == null) data.copy(hostKeys = data.hostKeys + offered) else data)
    }

    fun recordRejected(data: SshData, offered: TrustedHostKey): IosSshDataResult = if (!data.valid()) invalid(IosSshDataFailure.INVALID_DATA)
        else checked(data.copy(rejectedHostKeys = (data.rejectedHostKeys.filterNot { it.endpoint == offered.endpoint } + offered).takeLast(500)))

    /** User-confirmed trust reset retains the last rejected key, as on Android. */
    fun forgetHost(data: SshData, endpoint: String): IosSshDataResult = if (!data.valid()) invalid(IosSshDataFailure.INVALID_DATA)
        else checked(data.copy(hostKeys = data.hostKeys.filterNot { it.endpoint == endpoint }))

    fun previousRejected(data: SshData, offered: TrustedHostKey): TrustedHostKey? =
        distinctRejectedHostKey(offered, data.rejectedHostKeys.firstOrNull { it.endpoint == offered.endpoint })

    fun decodeImport(bytes: ByteArray): IosSshImportResult = try {
        IosSshImportResult(decodeSshProfileImport(bytes), null)
    } catch (error: SshProfileImportException) { IosSshImportResult(null, error.reason) }

    fun planImport(current: SshData, imported: SshProfileImport, keyRef: String?, generateId: () -> String): IosSshPlanResult = try {
        IosSshPlanResult(planSshProfileImport(current, imported, keyRef, generateId), null)
    } catch (error: SshProfileImportException) { IosSshPlanResult(null, error.reason) }

    fun applyImport(current: SshData, plan: SshImportPlan): IosSshImportApplyResult = try {
        IosSshImportApplyResult(applySshImportPlan(current, plan), null)
    } catch (error: SshProfileImportException) { IosSshImportApplyResult(null, error.reason) }

    /** Avoid a Cocoa `new`-family getter name at the Swift preview boundary. */
    fun importAddedCount(plan: SshImportPlan): Int = plan.newProfiles.size

    fun kexAlgorithms(): List<String> = SshAlgorithms.kex
    fun hostKeyAlgorithms(): List<String> = SshAlgorithms.hostKeys
    fun cipherAlgorithms(): List<String> = SshAlgorithms.ciphers
    fun macAlgorithms(): List<String> = SshAlgorithms.macs
    private fun checked(data: SshData): IosSshDataResult = if (data.valid()) IosSshDataResult(data, null) else invalid(IosSshDataFailure.INVALID_DATA)
    private fun invalid(failure: IosSshDataFailure) = IosSshDataResult(null, failure)
}
