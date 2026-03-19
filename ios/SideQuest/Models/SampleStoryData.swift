import Foundation

enum SampleStoryData {
    static let templeOfEchoes: StoryTemplate = {
        let nodes: [StoryNode] = [
            StoryNode(
                id: "start",
                title: "The Ancient Map",
                text: "While sorting through your pack after a long day of quests, you discover a weathered parchment tucked inside a side pocket. It's a map — hand-drawn, centuries old — pointing to a place called the Temple of Echoes. Legend says the temple holds the Resonance Stone, an artifact that amplifies the will of whoever possesses it. The ink is fading. If you're going to follow it, the time is now.",
                type: .narrative,
                choices: [],
                nextNodeId: "compass_found"
            ),
            StoryNode(
                id: "compass_found",
                title: "A Lucky Find",
                text: "Before setting out, you rummage through an old supply cache near the trailhead. Buried under rusted tools and moth-eaten cloth, your hand closes around something cool and heavy — a brass compass, still working. Its needle doesn't point north. It points toward the temple.",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Wayfinder's Compass", itemDescription: "An ancient brass compass whose needle points toward places of power rather than magnetic north.", itemRarity: .uncommon, gold: 15, diamonds: 0),
                nextNodeId: "crossroads"
            ),
            StoryNode(
                id: "crossroads",
                title: "The Crossroads",
                text: "The forest path splits. To the east, thin smoke curls above the canopy — a settlement, perhaps. To the west, pale blue lights drift between the trees like captured starlight. The compass needle wavers between both directions before settling westward. But smoke means people, and people mean information.",
                type: .decision,
                choices: [
                    StoryChoice(id: "east", text: "Follow the smoke east", nextNodeId: "village"),
                    StoryChoice(id: "west", text: "Investigate the lights west", nextNodeId: "ruins")
                ]
            ),
            // EAST BRANCH
            StoryNode(
                id: "village",
                title: "The Hermit's Clearing",
                text: "The smoke leads to a lone cabin in a clearing. An old woman sits by a fire, unsurprised by your arrival. \"Another seeker,\" she says. \"The temple tests all who enter. Take these — you'll need them more than I do.\" She presses a bundle of dried herbs into your hands and tells you the temple guardian respects those who show no fear.",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Healer's Herbs", itemDescription: "A bundle of rare dried herbs wrapped in woven grass. They pulse faintly with restorative energy.", itemRarity: .common, gold: 10, diamonds: 0),
                nextNodeId: "village_info"
            ),
            StoryNode(
                id: "village_info",
                title: "The Elder's Warning",
                text: "The old woman stirs the fire. \"Two paths lead inside,\" she says. \"The front gate opens for those bold enough to announce themselves. But there's a passage beneath the eastern wall — the builders' entrance. Quieter. Darker.\" She meets your eyes. \"Choose which kind of seeker you are.\"",
                type: .decision,
                choices: [
                    StoryChoice(id: "front_gate", text: "Take the front entrance — boldly", nextNodeId: "grand_hall"),
                    StoryChoice(id: "hidden_path", text: "Find the hidden passage", nextNodeId: "secret_passage")
                ]
            ),
            // WEST BRANCH
            StoryNode(
                id: "ruins",
                title: "The Luminous Ruins",
                text: "The lights lead to crumbling stone arches overgrown with glowing moss. This was once an outpost of the same civilization that built the temple. Among the rubble, a crystal shard pulses with inner light — a fragment of something larger. Ancient writing on the walls warns: \"The guardian sees truth. Deception feeds its strength.\"",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Glowing Shard", itemDescription: "A crystal fragment that emits a soft blue light. It hums when brought near other artifacts of the same origin.", itemRarity: .rare, gold: 20, diamonds: 1),
                nextNodeId: "ruins_choice"
            ),
            StoryNode(
                id: "ruins_choice",
                title: "Approaching the Temple",
                text: "The temple looms ahead, half-consumed by the forest. Vines crawl over massive stone blocks. You can see the main entrance — a grand archway flanked by weathered statues. But the crystal shard in your pack grows warmer as you pass the eastern wall, where roots have pulled apart the stonework, revealing a narrow gap.",
                type: .decision,
                choices: [
                    StoryChoice(id: "climb_in", text: "Enter through the main archway", nextNodeId: "grand_hall"),
                    StoryChoice(id: "squeeze_through", text: "Slip through the gap in the wall", nextNodeId: "secret_passage")
                ]
            ),
            // CONVERGING PATHS
            StoryNode(
                id: "grand_hall",
                title: "The Grand Hall",
                text: "You step into an enormous vaulted chamber. Pillars carved like twisted trees hold up a ceiling lost in shadow. Your footsteps echo endlessly. On a fallen pedestal near the center, something catches the light — a shield, remarkably intact, its surface etched with geometric patterns that seem to shift when you look away.",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Echoing Shield", itemDescription: "A ceremonial shield from the temple's grand hall. The geometric patterns on its face ripple like water when touched.", itemRarity: .rare, gold: 25, diamonds: 1),
                nextNodeId: "guardian_encounter"
            ),
            StoryNode(
                id: "secret_passage",
                title: "The Hidden Way",
                text: "The passage is narrow and dark. You feel your way along walls smooth as glass, descending deeper. The air grows thick with the smell of old stone and something else — ozone, like the air before a storm. In an alcove, draped over a hook as if left for you, hangs a cloak woven from material so dark it seems to drink the light.",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Shadow Cloak", itemDescription: "A cloak of impossibly dark material. When worn, your outline blurs and sounds around you become muffled.", itemRarity: .rare, gold: 20, diamonds: 1),
                nextNodeId: "trap_room"
            ),
            StoryNode(
                id: "guardian_encounter",
                title: "The Guardian Awakens",
                text: "A grinding sound fills the hall. One of the pillar-statues turns its head toward you — not a pillar at all, but a stone sentinel, dormant for centuries. Its eyes flare with amber light. \"SEEKER,\" it rumbles. \"STATE YOUR PURPOSE.\" The ground trembles with each word. You could stand your ground and answer honestly. Or you could try to rush past while it's still waking.",
                type: .decision,
                choices: [
                    StoryChoice(id: "stand_ground", text: "Stand your ground and speak truthfully", nextNodeId: "peaceful_path"),
                    StoryChoice(id: "rush_past", text: "Sprint past the guardian", nextNodeId: "fight_path")
                ]
            ),
            StoryNode(
                id: "trap_room",
                title: "The Architect's Test",
                text: "The passage opens into a chamber crisscrossed with thin beams of pale light. A pressure plate clicks under your foot. The beams begin to rotate slowly — a security system, ancient but still functioning. You can see the mechanism driving it — exposed gears on the far wall. But there's also a vent shaft above, just wide enough to crawl through.",
                type: .decision,
                choices: [
                    StoryChoice(id: "disarm", text: "Disarm the mechanism", nextNodeId: "clever_escape"),
                    StoryChoice(id: "vent", text: "Crawl through the vent shaft", nextNodeId: "peaceful_path")
                ]
            ),
            StoryNode(
                id: "peaceful_path",
                title: "The Guardian's Respect",
                text: "The sentinel studies you for a long moment. Then it steps aside, the amber light in its eyes softening to a warm gold. \"YOU CARRY NO MALICE. THE CHAMBER IS YOURS TO ENTER.\" It places something in your hand — a small medallion, still warm from within the stone.",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Guardian's Blessing", itemDescription: "A warm stone medallion given by the temple's guardian. It pulses gently in rhythm with your heartbeat.", itemRarity: .legendary, gold: 30, diamonds: 2),
                nextNodeId: "resonance_chamber"
            ),
            StoryNode(
                id: "fight_path",
                title: "A Narrow Escape",
                text: "You bolt. The sentinel's massive arm sweeps through the air behind you, close enough to feel the wind. Stone fragments shower down as its fist strikes a pillar. You tumble through an archway and slam a heavy door shut behind you. Your heart pounds. You made it — but the guardian's amber eyes still glow through the cracks in the door.",
                type: .narrative,
                choices: [],
                nextNodeId: "resonance_chamber"
            ),
            StoryNode(
                id: "clever_escape",
                title: "The Artificer's Prize",
                text: "You study the mechanism, tracing the gear patterns. There — a keystone gear. You wedge your blade into it and twist. The beams freeze, then fade. Silence. In the now-safe chamber, you find a set of finely crafted tools hidden behind the mechanism panel — the temple builders' own instruments.",
                type: .itemPickup,
                choices: [],
                reward: StoryReward(itemName: "Artificer's Tools", itemDescription: "Precision instruments used by the temple's original builders. Each tool is perfectly balanced and resistant to rust.", itemRarity: .uncommon, gold: 25, diamonds: 1),
                nextNodeId: "resonance_chamber"
            ),
            StoryNode(
                id: "resonance_chamber",
                title: "The Resonance Stone",
                text: "The inner chamber is circular, the ceiling open to the sky. In the center, floating above a stone pedestal, the Resonance Stone turns slowly. It's smaller than you expected — barely the size of your fist — but the air around it hums with contained power. You can feel it in your teeth, your bones. You could take it. Its power would be yours. Or you could leave it here, where it's been safe for millennia, and walk away richer in wisdom than in power.",
                type: .decision,
                choices: [
                    StoryChoice(id: "take_stone", text: "Take the Resonance Stone", nextNodeId: "ending_power"),
                    StoryChoice(id: "leave_stone", text: "Leave the Stone in its place", nextNodeId: "ending_wisdom")
                ]
            ),
            StoryNode(
                id: "ending_power",
                title: "The Bearer of Echoes",
                text: "Your fingers close around the Stone. Power floods through you — every sound sharpens, every thought crystallizes. The temple shudders. Dust falls from the ceiling. As you walk out into the sunlight, the Stone warm in your pack, you feel the weight of what you've claimed. The temple behind you falls silent for the first time in a thousand years. Whatever comes next, you are changed.",
                type: .ending,
                choices: [],
                reward: StoryReward(itemName: "Resonance Stone", itemDescription: "The legendary artifact of the Temple of Echoes. It amplifies the will of its bearer, turning intention into reality.", itemRarity: .legendary, gold: 50, diamonds: 5),
                endingTitle: "Bearer of Echoes"
            ),
            StoryNode(
                id: "ending_wisdom",
                title: "The Wise Seeker",
                text: "You lower your hand. The Stone continues its slow rotation, undisturbed. Something shifts in the room — the air grows lighter, warmer. A beam of sunlight finds the Stone and scatters into a thousand colors across the walls. You understand now. The temple wasn't guarding the Stone from the world. It was waiting for someone wise enough to leave it be. As you step outside, you feel a quiet certainty settle in your chest. Some powers are greater when they remain untouched.",
                type: .ending,
                choices: [],
                reward: StoryReward(itemName: "Echo of Wisdom", itemDescription: "Not a physical object but a permanent clarity of mind earned by choosing restraint over power. Your thoughts flow clearer.", itemRarity: .legendary, gold: 40, diamonds: 3),
                endingTitle: "The Wise Seeker"
            )
        ]

        return StoryTemplate(
            id: "temple_of_echoes",
            title: "The Temple of Echoes",
            themeDescription: "An ancient temple deep in the forest holds a legendary artifact. Navigate traps, a stone guardian, and your own ambition.",
            iconName: "building.columns.fill",
            nodes: nodes,
            startNodeId: "start"
        )
    }()

    static let allTemplates: [StoryTemplate] = [templeOfEchoes]
}
