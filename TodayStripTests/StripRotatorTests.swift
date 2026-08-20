import Testing
@testable import TodayStrip

@MainActor
@Suite("Strip rotation")
struct StripRotatorTests {
    private func item(_ kind: StripItemKind, _ priority: StripPriority) -> StripItem {
        StripItem(kind: kind, priority: priority, symbolName: "x", text: kind.rawValue)
    }

    @Test func showsTheHighestPriorityItemFirst() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal), item(.note, .ambient)])
        #expect(rotator.current?.kind == .event)
    }

    @Test func advancesOnlyAfterTheDwellTimeElapses() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal)])

        rotator.tick(1)
        #expect(rotator.current?.kind == .event)

        rotator.tick(StripPriority.normal.dwell)
        #expect(rotator.current?.kind == .weather)
    }

    @Test func wrapsAroundToTheStart() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal), item(.note, .ambient)])

        rotator.tick(StripPriority.normal.dwell + 0.1)
        rotator.tick(StripPriority.ambient.dwell + 0.1)
        rotator.tick(StripPriority.ambient.dwell + 0.1)

        #expect(rotator.current?.kind == .event)
    }

    @Test func aPinnedItemTakesTheStripAndStopsRotation() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal), item(.timer, .pinned)])
        #expect(rotator.current?.kind == .timer)

        rotator.tick(120)
        #expect(rotator.current?.kind == .timer)
    }

    @Test func rotationResumesWhenThePinnedItemDisappears() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.timer, .pinned)])
        rotator.setItems([item(.weather, .ambient), item(.event, .normal)])
        #expect(rotator.current?.kind == .event)
    }

    @Test func becomingUrgentInterruptsTheCurrentSlot() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal)])
        rotator.tick(StripPriority.normal.dwell + 0.1)
        #expect(rotator.current?.kind == .weather)

        rotator.setItems([item(.weather, .ambient), item(.event, .urgent)])
        #expect(rotator.current?.kind == .event)
    }

    /// Without this, an item sitting at `urgent` — a battery stuck at 8% — would re-interrupt on
    /// every refresh and the strip would never move again.
    @Test func aStandingUrgentItemDoesNotReinterrupt() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .urgent)])
        rotator.tick(StripPriority.urgent.dwell + 0.1)
        #expect(rotator.current?.kind == .weather)

        rotator.setItems([item(.weather, .ambient), item(.event, .urgent)])
        #expect(rotator.current?.kind == .weather)
    }

    @Test func pausingHoldsTheCurrentItem() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal)])
        rotator.pause()

        rotator.tick(120)
        #expect(rotator.current?.kind == .event)
    }

    @Test func aContentOnlyChangeKeepsTheSlotAndUpdatesTheText() {
        let rotator = StripRotator()
        rotator.setItems([item(.weather, .ambient), item(.event, .normal)])

        var updated = item(.event, .normal)
        updated.text = "Standup in 3m"
        rotator.setItems([item(.weather, .ambient), updated])

        #expect(rotator.current?.kind == .event)
        #expect(rotator.current?.text == "Standup in 3m")
    }

    @Test func anEmptyCandidateSetClearsTheStrip() {
        let rotator = StripRotator()
        rotator.setItems([item(.event, .normal)])
        rotator.setItems([])
        #expect(rotator.current == nil)
    }
}
