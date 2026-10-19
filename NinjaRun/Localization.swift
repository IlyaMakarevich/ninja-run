import Foundation

enum Lang: String, CaseIterable {
    case en, ru, es, de, it, fr, zh

    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .fr: return "Français"
        case .zh: return "中文"
        }
    }

    /// First supported language from the device settings, English otherwise.
    static var system: Lang {
        for id in Locale.preferredLanguages {
            if let l = Lang(rawValue: String(id.prefix(2)).lowercased()) { return l }
        }
        return .en
    }

    /// The user's choice if they made one in the game, otherwise the system language.
    static var current: Lang {
        get { UserDefaults.standard.string(forKey: "lang").flatMap(Lang.init(rawValue:)) ?? system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lang") }
    }
}

struct Strings {
    let subtitle, play, soundOn, soundOff, language, levels, back: String
    let pause, resume, restart, next, again, levelComplete, gameComplete: String
    /// Format: time left, best time, gold collected, gold total.
    let winStats: String
    let levelNames: [String]
    let hints: [String]
}

/// Current UI strings.
var L: Strings { Strings.table[Lang.current]! }

extension Strings {
    static let table: [Lang: Strings] = [
        .en: Strings(
            subtitle: "momentum · wall jumps · gold · mines",
            play: "Play", soundOn: "Sound: on", soundOff: "Sound: off", language: "Language",
            levels: "Levels", back: "‹ Back",
            pause: "Paused", resume: "Resume", restart: "Restart", next: "Next", again: "Retry",
            levelComplete: "Level complete!", gameComplete: "You beat the game!",
            winStats: "Time: %.1f   Best: %.1f   Gold: %d/%d",
            levelNames: ["First Steps", "Walls", "Hills", "Minefield", "The Key", "Bounce",
                         "Drones", "In the Crosshairs", "Rockets", "The Chase", "The Well", "Finale"],
            hints: [
                "Left side — run, right side — jump (hold to jump higher).\nHit the green switch, then run to the door.",
                "Jump next to a wall to kick off it.\nHold toward the wall to slide down safely.",
                "Slopes help you build speed. Gold adds time.",
                "Red things are mines. Don't touch them.",
                "Grab the key to open the wooden door.",
                "Orange pads launch you upward.",
                "Blue drones patrol the corridors. Jump over them!",
                "The turret aims with a delay. Keep moving!",
                "Rockets home in on you. Make them crash into blocks.",
                "Purple drones give chase when they spot you.",
                "Slide down the walls. Long falls are deadly.",
                "Everything you've learned. Good luck, ninja.",
            ]),
        .ru: Strings(
            subtitle: "инерция · прыжки от стен · золото · мины",
            play: "Играть", soundOn: "Звук: вкл", soundOff: "Звук: выкл", language: "Язык",
            levels: "Уровни", back: "‹ Назад",
            pause: "Пауза", resume: "Продолжить", restart: "Заново", next: "Дальше", again: "Ещё раз",
            levelComplete: "Уровень пройден!", gameComplete: "Игра пройдена!",
            winStats: "Время: %.1f   Рекорд: %.1f   Золото: %d/%d",
            levelNames: ["Первые шаги", "Стены", "Холмы", "Минное поле", "Ключ", "Батут",
                         "Дроны", "Под прицелом", "Ракеты", "Погоня", "Колодец", "Финал"],
            hints: [
                "Слева — бег, справа — прыжок (держи — выше).\nНажми зелёный переключатель, потом беги к двери.",
                "Прыгай у стены, чтобы оттолкнуться.\nЗажми направление к стене — будешь скользить и не разобьёшься.",
                "Склоны помогают разгоняться. Золото добавляет время.",
                "Красное — мины. Не касайся.",
                "Возьми ключ, чтобы открыть деревянную дверь.",
                "Оранжевые площадки подбрасывают вверх.",
                "Синие дроны патрулируют коридоры. Перепрыгивай!",
                "Турель целится с задержкой. Не стой на месте!",
                "Ракеты летят за тобой. Заставь их врезаться в блоки.",
                "Фиолетовые дроны бросаются в погоню, если увидят тебя.",
                "Спускайся, скользя по стенам. Падение с высоты смертельно.",
                "Всё, чему ты научился. Удачи, ниндзя.",
            ]),
        .es: Strings(
            subtitle: "inercia · saltos de pared · oro · minas",
            play: "Jugar", soundOn: "Sonido: sí", soundOff: "Sonido: no", language: "Idioma",
            levels: "Niveles", back: "‹ Atrás",
            pause: "Pausa", resume: "Continuar", restart: "Reiniciar", next: "Siguiente", again: "Otra vez",
            levelComplete: "¡Nivel superado!", gameComplete: "¡Juego completado!",
            winStats: "Tiempo: %.1f   Récord: %.1f   Oro: %d/%d",
            levelNames: ["Primeros pasos", "Paredes", "Colinas", "Campo minado", "La llave", "Rebote",
                         "Drones", "En la mira", "Cohetes", "Persecución", "El pozo", "Final"],
            hints: [
                "Izquierda — correr, derecha — saltar (mantén para saltar más alto).\nPulsa el interruptor verde y corre hacia la puerta.",
                "Salta junto a una pared para impulsarte.\nMantén la dirección hacia la pared para deslizarte sin peligro.",
                "Las pendientes te ayudan a ganar velocidad. El oro añade tiempo.",
                "Lo rojo son minas. No las toques.",
                "Coge la llave para abrir la puerta de madera.",
                "Las plataformas naranjas te lanzan hacia arriba.",
                "Los drones azules patrullan los pasillos. ¡Sáltalos!",
                "La torreta apunta con retraso. ¡No te quedes quieto!",
                "Los cohetes te persiguen. Haz que choquen contra los bloques.",
                "Los drones morados te persiguen si te ven.",
                "Baja deslizándote por las paredes. Las caídas altas son mortales.",
                "Todo lo que has aprendido. Suerte, ninja.",
            ]),
        .de: Strings(
            subtitle: "Schwung · Wandsprünge · Gold · Minen",
            play: "Spielen", soundOn: "Ton: an", soundOff: "Ton: aus", language: "Sprache",
            levels: "Level", back: "‹ Zurück",
            pause: "Pause", resume: "Weiter", restart: "Neustart", next: "Nächstes", again: "Nochmal",
            levelComplete: "Level geschafft!", gameComplete: "Spiel durchgespielt!",
            winStats: "Zeit: %.1f   Rekord: %.1f   Gold: %d/%d",
            levelNames: ["Erste Schritte", "Wände", "Hügel", "Minenfeld", "Der Schlüssel", "Trampolin",
                         "Drohnen", "Im Visier", "Raketen", "Verfolgung", "Der Schacht", "Finale"],
            hints: [
                "Links — laufen, rechts — springen (halten für höhere Sprünge).\nDrück den grünen Schalter, dann lauf zur Tür.",
                "Spring an einer Wand, um dich abzustoßen.\nHalte Richtung Wand, um sicher herunterzurutschen.",
                "Hänge helfen beim Beschleunigen. Gold gibt Extrazeit.",
                "Rot sind Minen. Nicht berühren!",
                "Hol den Schlüssel, um die Holztür zu öffnen.",
                "Orangefarbene Plattformen schleudern dich nach oben.",
                "Blaue Drohnen patrouillieren die Gänge. Spring drüber!",
                "Der Geschützturm zielt mit Verzögerung. Bleib in Bewegung!",
                "Raketen verfolgen dich. Lass sie gegen Blöcke krachen.",
                "Lila Drohnen jagen dich, sobald sie dich sehen.",
                "Rutsch an den Wänden hinunter. Tiefe Stürze sind tödlich.",
                "Alles, was du gelernt hast. Viel Glück, Ninja.",
            ]),
        .it: Strings(
            subtitle: "inerzia · salti dai muri · oro · mine",
            play: "Gioca", soundOn: "Audio: sì", soundOff: "Audio: no", language: "Lingua",
            levels: "Livelli", back: "‹ Indietro",
            pause: "Pausa", resume: "Riprendi", restart: "Ricomincia", next: "Avanti", again: "Riprova",
            levelComplete: "Livello completato!", gameComplete: "Gioco completato!",
            winStats: "Tempo: %.1f   Record: %.1f   Oro: %d/%d",
            levelNames: ["Primi passi", "Muri", "Colline", "Campo minato", "La chiave", "Trampolino",
                         "Droni", "Sotto tiro", "Razzi", "Inseguimento", "Il pozzo", "Finale"],
            hints: [
                "Sinistra — corri, destra — salta (tieni premuto per saltare più in alto).\nPremi l'interruttore verde, poi corri alla porta.",
                "Salta vicino a un muro per darti la spinta.\nTieni premuta la direzione del muro per scivolare in sicurezza.",
                "Le pendenze ti aiutano a prendere velocità. L'oro aggiunge tempo.",
                "Le cose rosse sono mine. Non toccarle.",
                "Prendi la chiave per aprire la porta di legno.",
                "Le piattaforme arancioni ti lanciano in alto.",
                "I droni blu pattugliano i corridoi. Saltali!",
                "La torretta mira in ritardo. Non stare fermo!",
                "I razzi ti inseguono. Falli schiantare contro i blocchi.",
                "I droni viola ti inseguono se ti vedono.",
                "Scendi scivolando lungo i muri. Le cadute dall'alto sono mortali.",
                "Tutto ciò che hai imparato. Buona fortuna, ninja.",
            ]),
        .fr: Strings(
            subtitle: "élan · sauts muraux · or · mines",
            play: "Jouer", soundOn: "Son : oui", soundOff: "Son : non", language: "Langue",
            levels: "Niveaux", back: "‹ Retour",
            pause: "Pause", resume: "Reprendre", restart: "Recommencer", next: "Suivant", again: "Rejouer",
            levelComplete: "Niveau terminé !", gameComplete: "Jeu terminé !",
            winStats: "Temps : %.1f   Record : %.1f   Or : %d/%d",
            levelNames: ["Premiers pas", "Murs", "Collines", "Champ de mines", "La clé", "Trampoline",
                         "Drones", "Dans le viseur", "Roquettes", "La poursuite", "Le puits", "Finale"],
            hints: [
                "Gauche — courir, droite — sauter (maintiens pour sauter plus haut).\nActive l'interrupteur vert, puis cours vers la porte.",
                "Saute contre un mur pour rebondir.\nMaintiens la direction du mur pour glisser sans danger.",
                "Les pentes t'aident à prendre de la vitesse. L'or ajoute du temps.",
                "Le rouge, ce sont des mines. N'y touche pas.",
                "Prends la clé pour ouvrir la porte en bois.",
                "Les plateformes orange te propulsent vers le haut.",
                "Les drones bleus patrouillent les couloirs. Saute par-dessus !",
                "La tourelle vise avec un temps de retard. Ne reste pas immobile !",
                "Les roquettes te poursuivent. Fais-les s'écraser contre les blocs.",
                "Les drones violets te prennent en chasse s'ils te voient.",
                "Descends en glissant le long des murs. Les chutes de haut sont mortelles.",
                "Tout ce que tu as appris. Bonne chance, ninja.",
            ]),
        .zh: Strings(
            subtitle: "惯性 · 蹬墙跳 · 金块 · 地雷",
            play: "开始游戏", soundOn: "声音：开", soundOff: "声音：关", language: "语言",
            levels: "关卡", back: "‹ 返回",
            pause: "暂停", resume: "继续", restart: "重新开始", next: "下一关", again: "再来一次",
            levelComplete: "过关！", gameComplete: "通关！",
            winStats: "时间：%.1f   最佳：%.1f   金块：%d/%d",
            levelNames: ["第一步", "墙壁", "山丘", "雷区", "钥匙", "弹跳",
                         "无人机", "瞄准之下", "火箭", "追击", "深井", "终章"],
            hints: [
                "左侧——奔跑，右侧——跳跃（按住跳得更高）。\n按下绿色开关，然后跑向门。",
                "贴着墙跳跃可以蹬墙弹开。\n按住朝向墙的方向，可以安全滑下。",
                "斜坡帮你加速。金块可以增加时间。",
                "红色的是地雷。别碰！",
                "拿到钥匙，打开木门。",
                "橙色跳板会把你弹向高处。",
                "蓝色无人机在走廊巡逻。跳过去！",
                "炮塔瞄准有延迟。别停下！",
                "火箭会追踪你。引它们撞上方块。",
                "紫色无人机一看到你就会追上来。",
                "贴着墙滑下去。从高处坠落会致命。",
                "运用你学到的一切。祝你好运，忍者。",
            ]),
    ]
}
