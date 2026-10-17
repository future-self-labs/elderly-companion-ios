import Foundation

/// Realistic Dutch sample data for mock mode: caregiver Anna de Vries cares for her father Wim
/// (beheerder) and reads along for her aunt Riet (lezer). Generated relative to "now" so the
/// dashboard always looks alive.
enum MockIDs {
    static let anna = "6F1C2B7E-1D7A-4E36-9C55-2F0B6A1C9D01"
    static let newCaregiver = "6F1C2B7E-1D7A-4E36-9C55-2F0B6A1C9D02"
    static let mark = "6F1C2B7E-1D7A-4E36-9C55-2F0B6A1C9D03"
    static let wim = "8E5C2D1A-4B7F-4C2A-9F3E-1A2B3C4D5E6F"
    static let riet = "3A9D7C21-5E4B-4F10-8B2C-7D6E5F4A3B21"
    static let wimDevice = "D3C1B2A0-0000-4000-8000-000000000001"
}

struct MockConversationTemplate {
    let summary: String
    let topics: [String]
    let mood: Double
    let clarity: Double
    let concern: Bool
    let moodIndicators: [String]
    let signals: [String]
    let people: [String]
    let places: [String]
    let dates: [String]
    let emotional: [String]
    let transcript: [(TranscriptRole, String)]

    /// Story conversations (v2.1 `mode: levensverhaal`); Wim's setting records those.
    var isStory: Bool { topics.contains("trouwdag") || topics.contains("Toon Hermans") }
}

enum MockData {
    static let templates: [MockConversationTemplate] = [
        MockConversationTemplate(
            summary: "Wim vertelde enthousiast over zijn moestuin: de tomaten zijn eindelijk rood. Hij bewaart er een paar voor kleindochter Sara, die zaterdag langskomt.",
            topics: ["moestuin", "kleindochter Sara"], mood: 4, clarity: 5, concern: false,
            moodIndicators: ["lachte veel", "klonk trots"], signals: [], people: ["Sara"], places: ["de moestuin"], dates: ["zaterdag"],
            emotional: ["glunderde toen hij over Sara sprak"],
            transcript: [(.noah, "Goedemiddag Wim! Hoe staan de tomaten erbij?"), (.oudere, "Ze zijn rood, eindelijk! Ik heb er een paar voor Sara bewaard."), (.noah, "Wat lief van u. Komt Sara binnenkort langs?"), (.oudere, "Zaterdag. Dan gaan we samen plukken.")]
        ),
        MockConversationTemplate(
            summary: "Rustig gesprek over de wandeling langs het Spaarne. Wim kwam een oud-collega tegen en haalde herinneringen op aan de Ritmeesterschool.",
            topics: ["wandelen", "oud-collega's"], mood: 4, clarity: 5, concern: false,
            moodIndicators: ["ontspannen"], signals: [], people: ["meester Bakker"], places: ["het Spaarne", "de Ritmeesterschool"], dates: ["1975"],
            emotional: [],
            transcript: [(.noah, "Heeft u vandaag al gewandeld?"), (.oudere, "Ja, langs het Spaarne. Ik zag Bakker nog, van school."), (.noah, "Wat leuk! Waar hadden jullie het over?"), (.oudere, "Over de schoolreisjes naar Artis. Dat waren tijden.")]
        ),
        MockConversationTemplate(
            summary: "Wim klonk moe en vertelde dat hij slecht had geslapen. Hij miste Margriet vandaag extra. Noah heeft rustig geluisterd en voorgesteld om Anna te bellen.",
            topics: ["slaap", "Margriet"], mood: 2, clarity: 4, concern: true,
            moodIndicators: ["zuchtte vaak", "korte antwoorden"], signals: ["Voelt zich eenzaam in de avond"], people: ["Margriet", "Anna"], places: [], dates: [],
            emotional: ["werd stil bij het noemen van Margriet"],
            transcript: [(.noah, "Goedemorgen Wim. Hoe heeft u geslapen?"), (.oudere, "Niet zo best. Ik lag veel wakker."), (.noah, "Dat is vervelend. Waar dacht u aan?"), (.oudere, "Aan Margriet. Ik mis haar vandaag."), (.noah, "Dat begrijp ik. Zal ik u helpen Anna even te bellen?")]
        ),
        MockConversationTemplate(
            summary: "Samen de uitslag van Ajax besproken (2–1 gewonnen). Wim lachte veel en vertelde over de wedstrijd die hij in 1972 met zijn vader zag.",
            topics: ["Ajax", "voetbal"], mood: 5, clarity: 5, concern: false,
            moodIndicators: ["lachte veel", "veel energie"], signals: [], people: ["zijn vader"], places: ["De Meer"], dates: ["1972"],
            emotional: ["ontroerd bij de herinnering aan zijn vader"],
            transcript: [(.noah, "Heeft u gezien dat Ajax gewonnen heeft?"), (.oudere, "Natuurlijk! 2–1. Wat een doelpunt in de laatste minuut."), (.noah, "U bent al lang supporter, toch?"), (.oudere, "Sinds 1972. Mijn vader nam me mee naar De Meer.")]
        ),
        MockConversationTemplate(
            summary: "Noah herinnerde Wim aan de afspraak bij de huisarts op dinsdag. Wim wil vragen naar zijn knie, die bij het wandelen pijn doet.",
            topics: ["huisarts", "knie"], mood: 3, clarity: 4, concern: false,
            moodIndicators: ["zakelijk"], signals: ["Knie doet pijn bij het wandelen"], people: ["dokter Smit"], places: [], dates: ["dinsdag"],
            emotional: [],
            transcript: [(.noah, "Denkt u aan de afspraak bij dokter Smit op dinsdag?"), (.oudere, "Ja, ik wil naar mijn knie laten kijken."), (.noah, "Goed idee. Zal ik u dinsdagochtend nog even bellen?"), (.oudere, "Graag.")]
        ),
        MockConversationTemplate(
            summary: "Wim vertelde over zijn trouwdag met Margriet in 1962: het regende, maar niemand ging naar binnen. Dit verhaal is bewaard in het levensverhaal.",
            topics: ["trouwdag", "Margriet"], mood: 4, clarity: 5, concern: false,
            moodIndicators: ["warm", "lachte"], signals: [], people: ["Margriet"], places: ["Haarlem", "de Bavo"], dates: ["1962"],
            emotional: ["glimlachte bij de herinnering aan de regen"],
            transcript: [(.noah, "U vertelde laatst dat het regende op uw trouwdag. Hoe ging dat?"), (.oudere, "Het goot! Maar niemand ging naar binnen."), (.noah, "Wat mooi. Wat deden jullie dan?"), (.oudere, "Dansen op het plein bij de Bavo. Margriet in haar witte jurk, kletsnat.")]
        ),
        MockConversationTemplate(
            summary: "Kort gesprek in de ochtend. Noah gaf het afgesproken geheugensteuntje voor na het ontbijt. Wim had zijn medicijndoos al klaarstaan en ging daarna met de fiets naar de markt.",
            topics: ["ochtend", "markt"], mood: 4, clarity: 5, concern: false,
            moodIndicators: ["opgewekt"], signals: [], people: [], places: ["de Grote Markt"], dates: [],
            emotional: [],
            transcript: [(.noah, "Goedemorgen Wim! Even het geheugensteuntje dat Anna heeft ingesteld: iets voor na het ontbijt."), (.oudere, "Dank je. Mijn medicijndoos staat al klaar."), (.noah, "Fijn. Wat gaat u vandaag doen?"), (.oudere, "Naar de markt, verse vis halen.")]
        ),
        MockConversationTemplate(
            summary: "Wim vertelde over een vreemd telefoontje van iemand die zei van de bank te zijn en om zijn pincode vroeg. Noah raadde aan niets door te geven en Anna te bellen.",
            topics: ["bank", "telefoontje"], mood: 3, clarity: 4, concern: true,
            moodIndicators: ["onrustig"], signals: ["Mogelijke oplichting via de telefoon"], people: ["Anna"], places: [], dates: ["vanochtend"],
            emotional: ["klonk ongerust"],
            transcript: [(.oudere, "Ik werd gebeld door de bank. Ze wilden mijn pincode."), (.noah, "Dat klinkt niet goed, Wim. Een bank vraagt nooit om uw pincode."), (.oudere, "Dat dacht ik al."), (.noah, "Geef niets door. Zal ik Anna laten weten wat er gebeurd is?"), (.oudere, "Ja, doe dat maar.")]
        ),
        MockConversationTemplate(
            summary: "Toon Hermans-avond: Wim droeg zijn favoriete gedicht voor en vertelde over de voorstelling in Carré in 1975.",
            topics: ["Toon Hermans", "Carré"], mood: 5, clarity: 5, concern: false,
            moodIndicators: ["lachte veel"], signals: [], people: ["Margriet"], places: ["Carré"], dates: ["1975"],
            emotional: ["genoot zichtbaar"],
            transcript: [(.noah, "Zullen we het over Toon Hermans hebben?"), (.oudere, "Graag! Weet je dat ik hem in Carré heb gezien?"), (.noah, "Wat bijzonder. Wanneer was dat?"), (.oudere, "In 1975, met Margriet. We hebben gehuild van het lachen.")]
        ),
        MockConversationTemplate(
            summary: "Gesprek over de kleinkinderen. Sara komt zaterdag langs en Wim wil samen appeltaart bakken volgens het recept van Margriet.",
            topics: ["kleinkinderen", "appeltaart"], mood: 4, clarity: 5, concern: false,
            moodIndicators: ["vrolijk"], signals: [], people: ["Sara", "Margriet"], places: [], dates: ["zaterdag"],
            emotional: [],
            transcript: [(.noah, "Wat gaat u zaterdag met Sara doen?"), (.oudere, "Appeltaart bakken. Het recept van Margriet."), (.noah, "Heerlijk. Weet u het recept nog uit uw hoofd?"), (.oudere, "Bijna. De kaneel moet er royaal in.")]
        ),
    ]

    /// Deterministic pseudo-random in 0..<1 for a seed.
    static func noise(_ seed: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 1013904223)
        x ^= x >> 13; x = x &* 0x5bd1e995; x ^= x >> 15
        return Double(x % 10_000) / 10_000
    }

    static func wimConversations(now: Date) -> [ConversationDetail] {
        var result: [ConversationDetail] = []
        let calendar = DutchFormat.calendar
        let channels: [ConversationChannel] = [.app, .telefoonUit, .app, .telefoonIn]
        var templateIndex = 0
        for dayOffset in 0..<30 {
            // Some days without a conversation, some with two.
            let count: Int
            let r = noise(dayOffset)
            if dayOffset == 0 { count = 1 } else if r < 0.15 { count = 0 } else if r > 0.75 { count = 2 } else { count = 1 }
            for slot in 0..<count {
                guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = slot == 0 ? 10 : 18
                components.minute = Int(noise(dayOffset * 7 + slot) * 50)
                guard var started = calendar.date(from: components) else { continue }
                if started > now { started = now.addingTimeInterval(-3600) }
                let template = templates[templateIndex % templates.count]
                templateIndex += 1
                let id = String(format: "C0A1B2C3-0000-4000-8000-%012d", result.count + 1)
                let duration = 240 + Int(noise(dayOffset * 13 + slot) * 1200)
                let lines = template.transcript.enumerated().map { index, line in
                    TranscriptLine(role: line.0, text: line.1, atSeconds: Double(index * 14 + 2))
                }
                result.append(ConversationDetail(
                    id: id,
                    startedAt: started,
                    durationSeconds: duration,
                    channel: channels[(result.count) % channels.count],
                    summary: template.summary,
                    moodScore: template.mood,
                    topics: template.topics,
                    hasConcern: template.concern,
                    moodIndicators: template.moodIndicators,
                    concerningSignals: template.signals,
                    cognitiveClarity: template.clarity,
                    mentionedPeople: template.people,
                    mentionedPlaces: template.places,
                    mentionedDates: template.dates,
                    emotionalMoments: template.emotional,
                    lifeStoryEntryIds: template.topics.contains("trouwdag") ? ["L0000000-0000-4000-8000-000000000003"]
                        : (template.topics.contains("Toon Hermans") ? ["L0000000-0000-4000-8000-000000000007"] : []),
                    transcript: lines,
                    mode: template.isStory ? .levensverhaal : .gesprek,
                    hasAudio: template.isStory
                ))
            }
        }
        return result.sorted { $0.startedAt > $1.startedAt }
    }

    static func rietConversations(now: Date) -> [ConversationDetail] {
        let calendar = DutchFormat.calendar
        return (0..<6).compactMap { index -> ConversationDetail? in
            guard let started = calendar.date(byAdding: .hour, value: -(index * 30 + 5), to: now) else { return nil }
            return ConversationDetail(
                id: String(format: "C1A1B2C3-0000-4000-8000-%012d", index + 1),
                startedAt: started,
                durationSeconds: 420 + index * 60,
                channel: index % 2 == 0 ? .telefoonIn : .app,
                summary: ["Riet vertelde over de bingo in het buurthuis. Ze had bijna gewonnen.",
                          "Gesprek over haar zus in Zeeland en de vakanties aan zee.",
                          "Riet had een fijne ochtend en heeft haar kamerplanten water gegeven.",
                          "Over vroeger: haar werk als naaister bij V&D.",
                          "Riet was wat moe, maar vrolijk. Ze keek uit naar het bezoek van haar buurvrouw.",
                          "Samen een woordspelletje gedaan. Riet wist bijna alle antwoorden."][index],
                moodScore: [4, 4, 5, 4, 3, 4][index],
                topics: [["bingo", "buurthuis"], ["Zeeland", "zus"], ["kamerplanten"], ["V&D", "naaien"], ["buurvrouw"], ["woordspel"]][index],
                hasConcern: false,
                moodIndicators: ["vrolijk"],
                concerningSignals: [],
                cognitiveClarity: 4,
                mentionedPeople: [],
                mentionedPlaces: [],
                mentionedDates: [],
                emotionalMoments: [],
                lifeStoryEntryIds: [],
                transcript: [TranscriptLine(role: .noah, text: "Goedemiddag Riet, hoe gaat het met u?", atSeconds: 1),
                             TranscriptLine(role: .oudere, text: "Goed hoor, dank je.", atSeconds: 6)],
                mode: .gesprek,
                hasAudio: false
            )
        }
    }

    static func wimLifeStory(now: Date) -> [LifeStoryEntry] {
        // Conversations 6 (trouwdag) and 9 (Toon Hermans) are recorded story conversations.
        func entry(_ n: Int, _ category: LifeStoryCategory, _ title: String, _ content: String, _ year: Int?, people: [String] = [], places: [String] = [], quote: String? = nil, by: CreatedBy = .noah, conversation: Int = 6, audioStart: Double?? = .none) -> LifeStoryEntry {
            let conversationId = String(format: "C0A1B2C3-0000-4000-8000-%012d", conversation)
            return LifeStoryEntry(
                id: String(format: "L0000000-0000-4000-8000-%012d", n),
                category: category, title: title, content: content, year: year,
                people: people, places: places, quote: quote,
                conversationId: by == .noah ? conversationId : nil,
                createdBy: by,
                createdAt: now.addingTimeInterval(TimeInterval(-n * 86_400 * 2)),
                audio: audioStart.map { LifeStoryAudio(conversationId: conversationId, startSeconds: $0, durationSeconds: MockRecording.durationSeconds) }
            )
        }
        return [
            entry(1, .jeugd, "De kruidenierswinkel van vader", "Wim groeide op boven de kruidenierswinkel van zijn vader in de Haarlemse Kleverlaan. Op zaterdag mocht hij de stroopwafels afwegen. Wie aardig was, kreeg er een gebroken exemplaar bij.", 1949, people: ["zijn vader"], places: ["Kleverlaan, Haarlem"], quote: "Een gebroken stroopwafel smaakt het lekkerst."),
            entry(2, .jeugd, "Schaatsen op het Spaarne", "In de strenge winter van 1956 lag het Spaarne helemaal dicht. Wim schaatste met zijn broer Kees tot aan Spaarndam en terug, met warme chocolademelk bij een koek-en-zopie onderweg.", 1956, people: ["Kees"], places: ["het Spaarne", "Spaarndam"]),
            entry(3, .familie, "De trouwdag met Margriet", "Het regende op 12 mei 1962, maar niemand ging naar binnen. Op het plein bij de Bavo werd gedanst, Margriet in haar witte jurk, kletsnat en lachend.", 1962, people: ["Margriet"], places: ["Grote Markt, Haarlem"], quote: "Niemand ging naar binnen.", audioStart: 6),
            entry(4, .werk, "Eerste dag voor de klas", "Op zijn eenentwintigste stond Wim voor het eerst voor de klas, 38 kinderen in de vierde klas van de Ritmeesterschool. Hij was zenuwachtiger dan zij.", 1963, places: ["Ritmeesterschool"], quote: "Ik was banger voor hen dan zij voor mij."),
            entry(5, .familie, "De geboorte van Anna", "Anna werd geboren op een zondagochtend in mei. Wim fietste in recordtijd naar het ziekenhuis en vergat zijn jas.", 1972, people: ["Anna", "Margriet"], places: ["Haarlem"]),
            entry(6, .reizen, "Met de Kever naar Italië", "In de zomer van 1968 reden Wim en Margriet met hun lichtblauwe Volkswagen Kever naar het Gardameer. Op de Brenner kookte de motor twee keer.", 1968, people: ["Margriet"], places: ["Gardameer", "Brennerpas"]),
            entry(7, .hobbys, "Toon Hermans in Carré", "Een avond die Wim nooit vergeet: Toon Hermans in Carré. Hij en Margriet huilden van het lachen.", 1975, people: ["Margriet"], places: ["Carré, Amsterdam"], conversation: 9, audioStart: .some(nil)),
            entry(8, .hobbys, "De moestuin aan de Kleverlaan", "Sinds 1985 heeft Wim een volkstuin. Hij kweekt tomaten, bonen en dahlia's, en deelt alles met de buren.", 1985, places: ["volkstuin Kleverlaan"]),
            entry(9, .belangrijkeMomenten, "Afscheid van de Ritmeesterschool", "Na veertig jaar nam Wim afscheid. De hele school zong in de gymzaal, en oud-leerlingen kwamen uit het hele land.", 2003, places: ["Ritmeesterschool"]),
            entry(10, .belangrijkeMomenten, "Het verlies van Margriet", "Margriet overleed in 2019. Wim praat er liever kort over, maar vertelt graag over hun mooie jaren.", 2019, people: ["Margriet"], by: .caregiver),
            entry(11, .dagelijksLeven, "Koffie om tien uur", "Elke ochtend om tien uur zet Wim koffie in de oude percolator van Margriet en leest hij het Haarlems Dagblad.", nil),
            entry(12, .dagelijksLeven, "Zaterdag met Sara", "Op zaterdag komt kleindochter Sara vaak langs. Dan bakken ze samen of gaan ze naar de tuin.", nil, people: ["Sara"]),
        ]
    }

    static func rietLifeStory(now: Date) -> [LifeStoryEntry] {
        [
            LifeStoryEntry(id: "L1000000-0000-4000-8000-000000000001", category: .werk, title: "Naaister bij V&D", content: "Riet werkte twintig jaar op het naaiatelier van V&D in Amersfoort.", year: 1960, people: [], places: ["Amersfoort"], quote: nil, conversationId: nil, createdBy: .noah, createdAt: now.addingTimeInterval(-86_400 * 5)),
            LifeStoryEntry(id: "L1000000-0000-4000-8000-000000000002", category: .reizen, title: "Zomers in Zeeland", content: "Elke zomer gingen Riet en haar zus naar Domburg.", year: 1955, people: ["haar zus"], places: ["Domburg"], quote: nil, conversationId: nil, createdBy: .noah, createdAt: now.addingTimeInterval(-86_400 * 9)),
        ]
    }

    static func wimReminders(now: Date) -> [Reminder] {
        let calendar = DutchFormat.calendar
        let tuesday: Date = {
            var date = now
            for _ in 0..<8 {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                if ReminderSchedule.isoWeekday(of: date) == 2 { break }
            }
            return DutchFormat.date(fromTime: "10:30", on: date)
        }()
        let sixDays = DutchFormat.date(fromTime: "09:00", on: calendar.date(byAdding: .day, value: 6, to: now) ?? now)
        func make(_ n: Int, _ title: String, _ notes: String?, _ type: ReminderType, _ schedule: ReminderSchedule, _ delivery: ReminderDelivery, active: Bool = true, by: CreatedBy = .caregiver) -> Reminder {
            Reminder(id: String(format: "R0000000-0000-4000-8000-%012d", n), title: title, notes: notes, type: type,
                     schedule: schedule, delivery: delivery, active: active, createdBy: by,
                     nextAt: active ? schedule.nextOccurrence(after: now) : nil, lastCompletedAt: nil)
        }
        return [
            make(1, "Pillen innemen", "De witte na het ontbijt", .medicatie, .daily(time: "08:30"), .inGesprek),
            make(2, "Afspraak bij de huisarts", "Dokter Smit, vragen naar de knie", .afspraak, .once(at: tuesday), .bellen),
            make(3, "Wandelen na de lunch", "Rondje langs het Spaarne", .routine, .weekly(time: "14:00", weekdays: [2, 4, 6]), .inGesprek),
            make(4, "Verjaardag van Sara", "Ze wordt 16! Kaartje sturen.", .verjaardag, .once(at: sixDays), .inGesprek, by: .noah),
            make(5, "Plantjes water geven", nil, .overig, .weekly(time: "10:00", weekdays: [1, 5]), .inGesprek),
            make(6, "Avondpillen", "Het kleine roze pilletje", .medicatie, .daily(time: "20:00"), .bellen, active: false),
        ]
    }
}
