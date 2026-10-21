import Foundation
import Testing
@testable import EAIPDataCore

@Suite("AIRAC page keep alive", .serialized)
@MainActor
struct AIRACPageLoaderTests {
    @MainActor
    final class Gate {
        private var continuation: CheckedContinuation<Int, Never>?
        private var observer: CheckedContinuation<Void, Never>?
        func value() async -> Int {
            await withCheckedContinuation {
                continuation = $0
                observer?.resume()
                observer = nil
            }
        }
        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func release(_ value: Int) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    @Test func returningToLoadedPageDoesNotFetchAgain() async {
        let page = AIRACPageLoader(initialValue: [Int]())
        var calls = 0
        for _ in 0..<3 {
            await page.load(key: "source1") { calls += 1; return [1, 2] }
        }
        #expect(calls == 1)
        #expect(page.value == [1, 2])
        #expect(!page.isLoading)
    }

    @Test func emptyResultAlsoStaysLoaded() async {
        let page = AIRACPageLoader(initialValue: [Int]())
        var calls = 0
        for _ in 0..<3 {
            await page.load(key: "source1") { calls += 1; return [] }
        }
        #expect(calls == 1)
    }

    @Test func explicitRefreshBypassesLoadedResult() async {
        let page = AIRACPageLoader(initialValue: 0)
        await page.load(key: "source1") { 1 }
        await page.load(key: "source1", force: true) { 2 }
        #expect(page.value == 2)
    }

    @Test func changingDataRevisionOrAirportReloadsPage() async {
        let page = AIRACPageLoader(initialValue: "")
        await page.load(key: "ZBAA|1") { "ZBAA old" }
        await page.load(key: "ZBAD|1") { "ZBAD" }
        #expect(page.value == "ZBAD")
        await page.load(key: "ZBAD|2") { "ZBAD new" }
        #expect(page.value == "ZBAD new")
    }

    @Test func leavingViewDoesNotCancelItsPendingRequest() async {
        let page = AIRACPageLoader(initialValue: 0)
        let gate = Gate()
        let viewTask = Task { await page.load(key: "source1") { await gate.value() } }
        await gate.waitUntilStarted()
        viewTask.cancel()
        #expect(page.isLoading)
        gate.release(42)
        await viewTask.value
        #expect(page.value == 42)
        #expect(page.errorMessage == nil)
        #expect(!page.isLoading)
    }

    @Test func returningWhileLoadingReusesThePendingRequest() async {
        let page = AIRACPageLoader(initialValue: 0)
        let gate = Gate()
        var calls = 0
        let first = Task { await page.load(key: "source1") { calls += 1; return await gate.value() } }
        await gate.waitUntilStarted()
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await page.load(key: "source1") { calls += 1; return -1 }
        }
        while !secondStarted { await Task.yield() }
        #expect(calls == 1)
        #expect(page.isLoading)
        gate.release(42)
        await first.value
        await second.value
        #expect(calls == 1)
        #expect(page.value == 42)
    }

    @Test func staleCompletionCannotOverwriteARefreshOrNewSource() async {
        for useSameKey in [false, true] {
            let page = AIRACPageLoader(initialValue: 0)
            let gate = Gate()
            let old = Task { await page.load(key: "source1") { await gate.value() } }
            await gate.waitUntilStarted()
            await page.load(key: useSameKey ? "source1" : "source2", force: useSameKey) { 2 }
            gate.release(1)
            await old.value
            #expect(page.value == 2)
            #expect(page.errorMessage == nil)
            #expect(!page.isLoading)
        }
    }

    @Test func failedLoadCanBeRetriedAndClearsItsError() async {
        let page = AIRACPageLoader(initialValue: 0)
        await page.load(key: "source1", errorPrefix: "加载失败：") { throw URLError(.notConnectedToInternet) }
        #expect(page.errorMessage?.hasPrefix("加载失败：") == true)
        #expect(!page.isLoading)
        await page.load(key: "source1") { 42 }
        #expect(page.value == 42)
        #expect(page.errorMessage == nil)
    }
}
