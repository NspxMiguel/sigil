import Foundation
import SwiftUI

enum Language: String, CaseIterable, Identifiable {
    case en
    case pt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .pt: return "Português"
        }
    }

    /// System language decides the default. `SIGIL_LANG` overrides it, which is
    /// how a translation gets checked without changing the machine's language.
    static var resolvedDefault: Language {
        if let forced = ProcessInfo.processInfo.environment["SIGIL_LANG"],
            let language = Language(rawValue: forced.lowercased().prefix(2).description)
        {
            return language
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("pt") ? .pt : .en
    }
}

@Observable
final class Localization {
    private static let storageKey = "selectedLanguage"

    var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        language = stored.flatMap(Language.init(rawValue:)) ?? Language.resolvedDefault
    }

    func callAsFunction(_ key: StringKey) -> String {
        key.value(for: language)
    }
}

enum StringKey {
    case appName
    case tagline

    case patchAction
    case patchActionBusy
    case chooseOwnImage
    case chooseOwnImagePrompt

    case catalogLoading
    case catalogOfflineTitle
    case catalogOfflineBody
    case catalogEmptyTitle
    case catalogEmptyBody
    case catalogSectionLabel
    case retry

    case contributeAction
    case contributeSubtitle

    case driveSectionLabel
    case noDriveTitle
    case noDriveBody
    case internalDriveExcluded
    case rescan
    case selectedImage

    case confirmTitle
    case confirmBody
    case confirmAction
    case cancel
    case succeeded
    case mailOpened
    case mailUnavailable
    case languageLabel

    func value(for language: Language) -> String {
        switch language {
        case .en: return english
        case .pt: return portuguese
        }
    }

    private var english: String {
        switch self {
        case .appName: return "Sigil"
        case .tagline: return "Put an unsupported NVMe in the PS5 expansion slot."

        case .patchAction: return "Patch your SSD"
        case .patchActionBusy: return "Patching…"
        case .chooseOwnImage: return "Use my own image"
        case .chooseOwnImagePrompt: return "Choose a header image"

        case .catalogLoading: return "Checking GitHub for published headers…"
        case .catalogOfflineTitle: return "Can't reach GitHub"
        case .catalogOfflineBody:
            return "The published headers could not be fetched. You can still point Sigil at an image file you already have."
        case .catalogEmptyTitle: return "No header published for current firmware"
        case .catalogEmptyBody:
            return "Nothing has been published for firmware past 4.03 yet. If you already have an image, use it below."
        case .catalogSectionLabel: return "Published headers"
        case .retry: return "Try again"

        case .contributeAction: return "Contribute a dump"
        case .contributeSubtitle:
            return "Already running a supported drive in your PS5? Read its header and help unblock this."

        case .driveSectionLabel: return "Connected drives"
        case .noDriveTitle: return "No external drive connected"
        case .noDriveBody: return "Connect the NVMe in a USB enclosure and it shows up here."
        case .internalDriveExcluded: return "Internal and boot volumes are never listed."
        case .rescan: return "Scan again"
        case .selectedImage: return "Image"

        case .confirmTitle: return "Write to this drive?"
        case .confirmBody:
            return "This overwrites the beginning of the destination drive and cannot be undone. Check the disk identifier before continuing."
        case .confirmAction: return "Write"
        case .cancel: return "Cancel"
        case .succeeded: return "Done. Put the drive in the console and see if it mounts."
        case .mailOpened:
            return "Saved, and a draft is open in your mail app with the dump attached. Nothing is sent until you press send."
        case .mailUnavailable:
            return "Saved. No mail app is configured, so send the file to \(ContributionMailer.recipient) yourself."
        case .languageLabel: return "Language"
        }
    }

    private var portuguese: String {
        switch self {
        case .appName: return "Sigil"
        case .tagline: return "Use um NVMe sem suporte no slot de expansão do PS5."

        case .patchAction: return "Preparar seu SSD"
        case .patchActionBusy: return "Preparando…"
        case .chooseOwnImage: return "Usar imagem própria"
        case .chooseOwnImagePrompt: return "Escolha uma imagem de cabeçalho"

        case .catalogLoading: return "Procurando cabeçalhos publicados no GitHub…"
        case .catalogOfflineTitle: return "Não deu para acessar o GitHub"
        case .catalogOfflineBody:
            return "Os cabeçalhos publicados não puderam ser baixados. Você ainda pode apontar o Sigil para um arquivo de imagem que já tenha."
        case .catalogEmptyTitle: return "Nenhum cabeçalho publicado para os firmwares atuais"
        case .catalogEmptyBody:
            return "Ainda não há nada publicado para firmware acima do 4.03. Se você já tem uma imagem, use ela abaixo."
        case .catalogSectionLabel: return "Cabeçalhos publicados"
        case .retry: return "Tentar de novo"

        case .contributeAction: return "Doar uma leitura"
        case .contributeSubtitle:
            return "Já tem um drive compatível rodando no seu PS5? Leia o cabeçalho dele e ajude a destravar isto."

        case .driveSectionLabel: return "Drives conectados"
        case .noDriveTitle: return "Nenhum drive externo conectado"
        case .noDriveBody: return "Ligue o NVMe numa case USB e ele aparece aqui."
        case .internalDriveExcluded: return "Volumes internos e de inicialização nunca são listados."
        case .rescan: return "Procurar de novo"
        case .selectedImage: return "Imagem"

        case .confirmTitle: return "Gravar neste drive?"
        case .confirmBody:
            return "Isto sobrescreve o começo do drive de destino e não tem volta. Confira o identificador do disco antes de continuar."
        case .confirmAction: return "Gravar"
        case .cancel: return "Cancelar"
        case .succeeded: return "Pronto. Ponha o drive no console e veja se ele monta."
        case .mailOpened:
            return "Salvo, e abriu um rascunho no seu app de e-mail com a leitura anexada. Nada é enviado até você apertar enviar."
        case .mailUnavailable:
            return "Salvo. Não há app de e-mail configurado, então mande o arquivo para \(ContributionMailer.recipient) você mesmo."
        case .languageLabel: return "Idioma"
        }
    }
}
