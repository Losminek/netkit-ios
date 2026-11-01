package cz.netkit.shared

import cz.netkit.shared.ios.*
import cz.netkit.shared.ssh.*
import kotlinx.coroutines.test.runTest
import kotlin.random.Random
import kotlin.test.*

class IosSshBridgeTest {
    private val domain = IosSshDomain()
    private fun profile(host: String = "192.0.2.1", secretRef: String? = null) = assertNotNull(domain.profile(
        "profile-a", "Test target", host, 22, "tester", SshAuthentication.PASSWORD, secretRef, null, "", 30))
    private fun key(blob: String) = TrustedHostKey("[192.0.2.1]:22", "ssh-ed25519", blob, "SHA256:$blob")

    @Test fun metadataRoundTripIsBoundedStrictAndVersioned() {
        val data = assertNotNull(domain.upsertProfile(domain.emptyData(), profile()).data)
        val bytes = assertNotNull(domain.encodeData(data))
        assertEquals(data, domain.decodeData(bytes).data)
        assertEquals(IosSshDataFailure.SIZE, domain.decodeData(ByteArray(1_048_577)).failure)
        assertEquals(IosSshDataFailure.UTF8, domain.decodeData(byteArrayOf(0xC3.toByte())).failure)
        assertEquals(IosSshDataFailure.FORMAT, domain.decodeData("[]".encodeToByteArray()).failure)
        assertEquals(IosSshDataFailure.SCHEMA, domain.decodeData("{\"schema\":2}".encodeToByteArray()).failure)
        assertEquals(IosSshDataFailure.SCHEMA, domain.decodeData("{\"schema\":\"1\"}".encodeToByteArray()).failure)
        assertEquals(IosSshDataFailure.FORMAT, domain.decodeData("{\"schema\":1,\"unexpected\":true}".encodeToByteArray()).failure)
        val deep = "{\"schema\":1,\"unexpected\":" + "[".repeat(20) + "0" + "]".repeat(20) + "}"
        assertEquals(IosSshDataFailure.FORMAT, domain.decodeData(deep.encodeToByteArray()).failure)
    }

    @Test fun tofuCannotReplaceTrustedKeyAndResetRetainsRejectedEvidence() {
        val runtimeBlob = Random.nextBytes(32).joinToString("") { it.toUByte().toString(16).padStart(2, '0') }
        val offered = key(runtimeBlob)
        val changed = key(runtimeBlob + "changed")
        assertEquals(HostKeyDecision.UNKNOWN, domain.hostDecision(domain.emptyData(), offered))
        val trusted = assertNotNull(domain.trustUnknown(domain.emptyData(), offered).data)
        assertEquals(HostKeyDecision.TRUSTED, domain.hostDecision(trusted, offered))
        assertEquals(HostKeyDecision.CHANGED, domain.hostDecision(trusted, changed))
        assertEquals(IosSshDataFailure.CONFLICT, domain.trustUnknown(trusted, changed).failure)
        val rejected = assertNotNull(domain.recordRejected(trusted, changed).data)
        val reset = assertNotNull(domain.forgetHost(rejected, offered.endpoint).data)
        assertTrue(reset.hostKeys.isEmpty())
        assertEquals(listOf(changed), reset.rejectedHostKeys)
        assertNull(domain.previousRejected(reset, changed))
        assertEquals(changed, domain.previousRejected(reset, offered))
    }

    @Test fun profileImportPreviewDetachesCredentialsAndRejectsStalePlan() {
        val before = assertNotNull(domain.upsertProfile(domain.emptyData(), profile(secretRef = "credential-a")).data)
        val document = """{"format":"netkit-ssh-profiles","schema":1,"profiles":[{"alias":"Test target","host":"192.0.2.2","port":22,"username":"tester"}],"skipped":[]}"""
        val incoming = assertNotNull(domain.decodeImport(document.encodeToByteArray()).imported)
        val plan = assertNotNull(domain.planImport(before, incoming, null) { "profile-b" }.plan)
        assertEquals(listOf("credential-a"), plan.detachedSecretRefs)
        val after = assertNotNull(domain.applyImport(before, plan).data)
        assertEquals("192.0.2.2", after.profiles.single().host)
        assertNull(after.profiles.single().secretRef)
        assertEquals(SshProfileImportFailure.STALE_PLAN, domain.applyImport(after, plan).failure)
        assertEquals(SshProfileImportFailure.SIZE, domain.decodeImport(ByteArray(SSH_PROFILE_IMPORT_LIMIT + 1)).failure)
        val runtimeValue = Random.nextBytes(16).joinToString("") { it.toUByte().toString(16) }
        val withCredential = document.replace("\"username\":\"tester\"", "\"username\":\"tester\",\"password\":\"$runtimeValue\"")
        assertEquals(SshProfileImportFailure.UNKNOWN_FIELD, domain.decodeImport(withCredential.encodeToByteArray()).failure)
    }

    @Test fun terminalPreservesStyledOutputAndSharedKeyEncoding() {
        val terminal = IosTerminal(80, 24)
        terminal.feed("\u001b[31mred\u001b[0m\u001b[?1h")
        assertTrue(terminal.snapshot().screen.first().text.startsWith("red"))
        assertEquals(1, terminal.snapshot().screen.first().runs.first().foreground)
        assertEquals("\u001bOA", terminal.keySequence(TerminalKey.UP, false, false, false))
        assertEquals("\u0003", terminal.textSequence("c", true, false))
        terminal.resize(999, 999)
        assertEquals(100, terminal.snapshot().screen.size)
        assertEquals(240, terminal.snapshot().screen.first().text.length)
    }

    @Test fun compositionIsBoundedAndPasteCannotInjectControls() {
        val terminal = IosTerminal(80, 24)
        terminal.composeSet("a😀")
        assertTrue(terminal.composeDelete(1, 0, true))
        terminal.composeFinish()
        assertEquals("a", terminal.drainInput())
        terminal.composeCommit("text")
        terminal.composeCommit("\n")
        assertEquals("text\r", terminal.drainInput())
        terminal.composeCommit("x".repeat(16_384))
        terminal.composeCommit("y")
        assertNull(terminal.drainInput())
        assertEquals("", terminal.drainInput())
        assertTrue(terminal.pasteNeedsConfirmation("a\n\u001bb"))
        assertEquals("a  b", terminal.safePaste("a\n\u001bb"))
    }

    @Test fun lifecycleUsesSharedMonotonicGraceAndPromptLimits() {
        var now = 1_000L
        val lifecycle = IosSshLifecycle { now }
        lifecycle.background()
        assertEquals(300_000L, lifecycle.remainingMillis())
        now += 299_999
        assertFalse(lifecycle.expired())
        now++
        assertTrue(lifecycle.foreground())
        assertNull(lifecycle.remainingMillis())
        assertEquals(180_000L, lifecycle.promptTimeoutMillis())
        assertEquals(600_000L, lifecycle.handshakeTimeoutMillis())
    }

    @Test fun sharedSecretStoreAndSwiftResultsUseSameBackendAndSurfaceFailures() = runTest {
        val backend = MemorySecrets()
        val adapter = IosSecretStoreAdapter(backend)
        val shared: SecretStore = adapter.sharedStore
        val material = Random.nextBytes(32)
        val secondMaterial = Random.nextBytes(32)
        shared.put("credential-a", material)
        assertContentEquals(material, adapter.getSecret("credential-a").bytes)
        assertContentEquals(material, shared.get("credential-a"))
        shared.delete("credential-a")
        assertNull(shared.get("credential-a"))
        backend.failure = SshFailure.SECRET_UNAVAILABLE
        assertEquals(SshFailure.SECRET_UNAVAILABLE, adapter.putSecret("credential-a", secondMaterial))
        assertEquals(SshFailure.SECRET_UNAVAILABLE, assertFailsWith<IosSecretStoreException> { shared.put("credential-a", secondMaterial) }.failure)
        assertFailsWith<IosSecretStoreException> { shared.get("credential-a") }
        assertFailsWith<IosSecretStoreException> { shared.delete("credential-a") }
        assertNull(adapter.getSecret("credential-a").bytes)
    }

    @Test fun profileEndpointChangeDetachesSavedPasswordAndKeyMetadataIsValidated() {
        val before = assertNotNull(domain.upsertProfile(domain.emptyData(), profile(secretRef = "credential-a")).data)
        val changed = assertNotNull(domain.upsertProfile(before, profile("192.0.2.2", "credential-a")).data)
        assertNull(changed.profiles.single().secretRef)
        val same = assertNotNull(domain.upsertProfile(before, profile(secretRef = "credential-a")).data)
        assertEquals("credential-a", same.profiles.single().secretRef)
        val publicValue = Random.nextBytes(32).joinToString("") { it.toUByte().toString(16) }
        val withKey = assertNotNull(domain.upsertKey(before, SshKeyInfo("key-a", "Test key", publicValue)).data)
        assertEquals(1, withKey.keys.size)
        assertEquals(IosSshDataFailure.INVALID_DATA, domain.upsertKey(withKey, SshKeyInfo("invalid/id", "Test", publicValue)).failure)
    }

    @Test fun deletionPreservesReferencedKeysAndRejectsStaleOrInvalidMetadata() {
        val publicValue = Random.nextBytes(32).joinToString("") { it.toUByte().toString(16) }
        val original = SshData(profiles = listOf(profile().copy(keyRef = "key-a")),
            keys = listOf(SshKeyInfo("key-a", "Test key", publicValue)))
        assertEquals(IosSshDataFailure.CONFLICT, domain.deleteKey(original, "key-a").failure)
        assertEquals(IosSshDataFailure.CONFLICT, domain.deleteProfile(original, "missing").failure)
        val withoutProfile = assertNotNull(domain.deleteProfile(original, "profile-a").data)
        assertTrue(withoutProfile.profiles.isEmpty())
        assertEquals(original.keys, withoutProfile.keys)
        val withoutKey = assertNotNull(domain.deleteKey(withoutProfile, "key-a").data)
        assertTrue(withoutKey.keys.isEmpty())
        assertEquals(IosSshDataFailure.CONFLICT, domain.deleteKey(withoutKey, "key-a").failure)
        assertEquals(IosSshDataFailure.INVALID_DATA, domain.deleteProfile(original.copy(schema = 2), "profile-a").failure)
        assertEquals(IosSshDataFailure.INVALID_DATA, domain.deleteKey(original.copy(schema = 2), "key-a").failure)
        assertEquals("key-a", original.profiles.single().keyRef)
    }

    @Test fun importEndpointPreviewIncludesUserAndIpv6AndPreservesKeyReference() {
        val originalProfile = profile(secretRef = "credential-a").copy(host = "2001:db8::1", keyRef = "key-a")
        val before = SshData(profiles = listOf(originalProfile))
        val incoming = SshProfileImport(listOf(SshImportProfile("Test target", "2001:db8::2", 2222, "operator")), emptyList())
        val plan = assertNotNull(domain.planImport(before, incoming, null) { "profile-b" }.plan)
        val change = domain.importChangedEndpoints(plan).single()
        assertEquals("profile-a", change.profileId)
        assertEquals("tester@[2001:db8::1]:22", change.before)
        assertEquals("operator@[2001:db8::2]:2222", change.after)
        assertEquals(listOf("credential-a"), domain.importDetachedRefs(plan))
        val applied = assertNotNull(domain.applyImport(before, plan).data)
        assertNull(applied.profiles.single().secretRef)
        assertEquals("key-a", applied.profiles.single().keyRef)
        val edited = assertNotNull(domain.upsertProfile(before, originalProfile.copy(host = "2001:db8::2")).data)
        assertEquals("key-a", edited.profiles.single().keyRef)
        val unchanged = assertNotNull(domain.planImport(applied, incoming, null) { "profile-b" }.plan)
        assertTrue(domain.importChangedEndpoints(unchanged).isEmpty())
        assertTrue(domain.importDetachedRefs(unchanged).isEmpty())
    }

    private class MemorySecrets : IosSecretBackend {
        private val items = mutableMapOf<String, ByteArray>()
        var failure: SshFailure? = null
        override fun store(id: String, bytes: ByteArray): SshFailure? {
            if (failure == null) items[id] = bytes.copyOf()
            return failure
        }
        override fun read(id: String): IosSecretReadResult = IosSecretReadResult(items[id]?.copyOf(), failure)
        override fun remove(id: String): SshFailure? {
            if (failure == null) items.remove(id)
            return failure
        }
    }
}
