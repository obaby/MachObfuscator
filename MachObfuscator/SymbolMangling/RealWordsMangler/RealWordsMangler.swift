import Foundation

class RealWordsMangler: SymbolMangling {
    static var key: String = "realWords"
    static let helpDescription: String = "replace objc symbols with random words (dyld info obfuscation not supported yet)"

    private let exportTrieMangler: ExportTrieMangling = ExportTrieMangler()

    required init() {}

    func mangleSymbols(_ symbols: ObfuscationSymbols) -> SymbolManglingMap {
        return mangleSymbols(symbols,
                             sentenceGenerator: EnglishSentenceGenerator())
    }

    func mangleSymbols(_ symbols: ObfuscationSymbols,
                       sentenceGenerator: SentenceGenerator) -> SymbolManglingMap {
        let mangledSelectorsBlacklist = (Array(symbols.blacklist.selectors) + Array(symbols.whitelist.selectors)).uniq
        let mangledClassesBlacklist = (Array(symbols.blacklist.classes) + Array(symbols.whitelist.classes)).uniq
        let unmangledAndMangledNonSetterPairs: [(String, String)] =
            symbols.whitelist
            .selectors
            .filter { !$0.isSetter }
            .compactMap { selector in
                while let randomSelector = sentenceGenerator.getUniqueSentence(length: selector.count) {
                    if !mangledSelectorsBlacklist.contains(randomSelector) {
                        return (selector, randomSelector)
                    }
                }
                return nil
            }

        let unmangledAndMangledSetterPairs: [(String, String)] =
            symbols.whitelist
            .selectors
            .filter { $0.isSetter }
            .compactMap { setter in
                guard let getter = setter.getterFromSetter,
                    let mangledGetter = unmangledAndMangledNonSetterPairs.first(where: { $0.0 == getter })?.1,
                    let mangledSetter = mangledGetter.setterFromGetter else {
                    return nil
                }
                return (setter, mangledSetter)
            }

        let unmangledAndMangledSelectorPairs: [(String, String)] =
            unmangledAndMangledNonSetterPairs + unmangledAndMangledSetterPairs

        let unmangledAndMangledClassPairs: [(String, String)] =
            symbols.whitelist
            .classes
            .compactMap { className in
                while let randomClassName = sentenceGenerator.getUniqueSentence(length: className.count)?.capitalizedOnFirstLetter {
                    if !mangledClassesBlacklist.contains(randomClassName) {
                        return (className, randomClassName)
                    }
                }
                return nil
            }

        let identityManglingMap =
            symbols.exportTriesPerCpuIdPerURL
            .mapValues { exportTriesPerCpuId in
                exportTriesPerCpuId.mapValues { ($0, exportTrieMangler.mangle(trie: $0, fillingRootLabelWith: 0)) }
            }

        return SymbolManglingMap(selectors: Dictionary(uniqueKeysWithValues: unmangledAndMangledSelectorPairs),
                                 classNames: Dictionary(uniqueKeysWithValues: unmangledAndMangledClassPairs),
                                 unobfuscatedObfuscatedTriePairPerCpuIdPerURL: identityManglingMap)
    }
}

extension String {
    var isSetter: Bool {
        let prefix = "set"
        guard count >= 5,
            hasPrefix(prefix),
            hasSuffix(":") else {
            return false
        }
        let firstGetterLetter = self[index(startIndex, offsetBy: 3)]
        return ("A" ... "Z").contains(firstGetterLetter)
    }

    var getterFromSetter: String? {
        guard isSetter else {
            return nil
        }
        let getterPart = dropFirst(3).dropLast()
        return getterPart.prefix(1).lowercased() + getterPart.dropFirst()
    }

    var setterFromGetter: String? {
        return "set" + prefix(1).uppercased() + dropFirst(1) + ":"
    }
}
