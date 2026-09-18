import Foundation

struct PaliQuote: Equatable, Identifiable {
    let id: Int
    let pali: String
    let translation: String
    let source: String

    static let collection: [PaliQuote] = [
        .init(id: 21, pali: "Appamādo amatapadaṁ", translation: "La atención diligente es el camino hacia lo inmortal.", source: "Dhammapada 21"),
        .init(id: 5, pali: "Na hi verena verāni", translation: "El odio nunca cesa con odio; cesa mediante el no-odio.", source: "Dhammapada 5"),
        .init(id: 183, pali: "Sabbapāpassa akaraṇaṁ, kusalassa upasampadā", translation: "No hacer el mal y cultivar el bien.", source: "Dhammapada 183"),
        .init(id: 277, pali: "Sabbe saṅkhārā aniccā", translation: "Todas las cosas condicionadas son impermanentes.", source: "Dhammapada 277"),
        .init(id: 160, pali: "Attā hi attano nātho", translation: "Uno mismo es su propio refugio.", source: "Dhammapada 160"),
        .init(id: 223, pali: "Akkodhena jine kodhaṁ", translation: "Vence la ira mediante la no-ira.", source: "Dhammapada 223"),
        .init(id: 184, pali: "Khantī paramaṁ tapo titikkhā", translation: "La paciencia es la práctica más elevada.", source: "Dhammapada 184"),
        .init(id: 202, pali: "Natthi santiparaṁ sukhaṁ", translation: "No hay felicidad mayor que la paz.", source: "Dhammapada 202"),
        .init(id: 194, pali: "Sukhā saṅghassa sāmaggī", translation: "Feliz es la armonía de la comunidad.", source: "Dhammapada 194"),
        .init(id: 204, pali: "Ārogyaparamā lābhā, santuṭṭhiparamaṁ dhanaṁ", translation: "La salud es la mayor ganancia; el contentamiento, la mayor riqueza.", source: "Dhammapada 204"),
        .init(id: 1, pali: "Manopubbaṅgamā dhammā, manoseṭṭhā manomayā", translation: "La mente precede a los fenómenos, los dirige y les da forma.", source: "Dhammapada 1"),
        .init(id: 2, pali: "Manasā ce pasannena, tato naṁ sukhamanveti, chāyāva anapāyinī", translation: "Cuando se actúa con una mente serena, la felicidad sigue como una sombra inseparable.", source: "Dhammapada 2"),
        .init(id: 12, pali: "Sārañca sārato ñatvā, asārañca asārato", translation: "Reconoce lo esencial como esencial y lo que no lo es como no esencial.", source: "Dhammapada 12"),
        .init(id: 25, pali: "Uṭṭhānenappamādena, saṁyamena damena ca", translation: "Con esfuerzo, diligencia, disciplina y dominio de uno mismo, la persona sabia construye una isla firme.", source: "Dhammapada 25"),
        .init(id: 35, pali: "Cittassa damatho sādhu, cittaṁ dantaṁ sukhāvahaṁ", translation: "Es bueno entrenar la mente; una mente entrenada trae bienestar.", source: "Dhammapada 35"),
        .init(id: 50, pali: "Attanova avekkheyya, katāni akatāni ca", translation: "Observa en ti mismo lo que has hecho y lo que aún queda por hacer.", source: "Dhammapada 50"),
        .init(id: 81, pali: "Selo yathā ekaghano, vātena na samīrati", translation: "Como una roca sólida no se mueve con el viento, la persona sabia no se agita por elogios o reproches.", source: "Dhammapada 81"),
        .init(id: 82, pali: "Yathāpi rahado gambhīro, vippasanno anāvilo", translation: "Al escuchar el Dhamma, la mente sabia se aclara como un lago profundo y sereno.", source: "Dhammapada 82"),
        .init(id: 100, pali: "Ekaṁ atthapadaṁ seyyo, yaṁ sutvā upasammati", translation: "Mejor una sola enseñanza con sentido que, al escucharla, trae paz.", source: "Dhammapada 100"),
        .init(id: 103, pali: "Ekañca jeyyamattānaṁ", translation: "Conquistarse a uno mismo es la victoria más elevada.", source: "Dhammapada 103"),
        .init(id: 276, pali: "Tumhehi kiccamātappaṁ, akkhātāro tathāgatā", translation: "El esfuerzo debe hacerlo cada uno; los Tathāgatas muestran el camino.", source: "Dhammapada 276"),
        .init(id: 279, pali: "Sabbe dhammā anattā", translation: "Todos los fenómenos carecen de un yo permanente.", source: "Dhammapada 279")
    ]

    static func forTimelapse(_ url: URL) -> PaliQuote {
        // Stable FNV-1a: the same timelapse always keeps the same quotation.
        let hash = url.lastPathComponent.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return collection[Int(hash % UInt64(collection.count))]
    }
}
