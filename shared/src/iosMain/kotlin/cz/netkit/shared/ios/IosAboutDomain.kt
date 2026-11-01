package cz.netkit.shared.ios

import cz.netkit.shared.update.privacyPolicyUrl

/** Fixed project links for About; the caller supplies the current language code. */
class IosAboutDomain {
    fun privacyUrl(language: String): String {
        val base = if (language.lowercase() == "cs") {
            "https://www.daniel.losak.cz/netkit"
        } else {
            "https://www.daniel.losak.cz/en/netkit"
        }
        return privacyPolicyUrl(base, "https://github.com/Losminek/netkit-ios", language)
    }
}
