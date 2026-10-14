import Foundation
import Testing
@testable import MediaModule

@Suite struct AppleMusicAccountTests {
    let store = FakeTokenStore()

    func account(_ store: FakeTokenStore? = nil) -> AppleMusicAccount {
        AppleMusicAccount(tokens: store ?? self.store)
    }

    let credentials = AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn")

    // MARK: status

    @Test func theStatusLinesAreTheOnesTheSettingsShow() {
        #expect(AppleMusicAccount.Status.notConnected.text == "Chưa kết nối")
        #expect(AppleMusicAccount.Status.connected(storefront: "vn").text == "Đã kết nối (vn)")
        #expect(AppleMusicAccount.Status.needsReauth.text == "Cần đăng nhập lại")
    }

    @Test func onlyConnectedCanAskApple() {
        #expect(!AppleMusicAccount.Status.notConnected.isConnected)
        #expect(AppleMusicAccount.Status.connected(storefront: "vn").isConnected)
        #expect(!AppleMusicAccount.Status.needsReauth.isConnected)
    }

    @Test func creatingTheAccountReadsNothing() {
        let tokens = FakeTokenStore.connected()
        let account = account(tokens)
        #expect(tokens.loadCount == 0)
        #expect(account.status == .notConnected)
    }

    @Test func loadingFindsAnEarlierSignIn() {
        let tokens = FakeTokenStore.connected(storefront: "us")
        let account = account(tokens)
        account.load()
        #expect(account.status == .connected(storefront: "us"))
        #expect(account.credentials == AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "us"))
    }

    @Test(arguments: [AppleMusicSecret.developerToken, .mediaUserToken, .storefront])
    func aStoreMissingAnyPartIsNotConnected(missing: AppleMusicSecret) {
        let tokens = FakeTokenStore.connected()
        tokens.remove(missing)
        let account = account(tokens)
        account.load()
        #expect(account.status == .notConnected)
        #expect(account.credentials == nil)
    }

    @Test func anEmptyStoreIsNotConnected() {
        let account = account()
        account.load()
        #expect(account.status == .notConnected)
        #expect(account.credentials == nil)
    }

    @Test func loadingHappensOnce() {
        let tokens = FakeTokenStore.connected()
        let account = account(tokens)
        account.load()
        account.markNeedsReauth()
        account.load()
        #expect(account.status == .needsReauth)
    }

    // MARK: connect

    @Test func connectingStoresAllThreeAndShowsTheStorefront() {
        let account = account()
        #expect(account.connect(credentials))
        #expect(account.status == .connected(storefront: "vn"))
        #expect(store.values == [.developerToken: "dev-token-fake", .mediaUserToken: "user-token-fake", .storefront: "vn"])
        #expect(account.credentials == credentials)
    }

    @Test func connectingNeedsTheStorefront() {
        let account = account()
        var incomplete = credentials
        incomplete.storefront = nil
        #expect(!account.connect(incomplete))
        #expect(account.status == .notConnected)
        #expect(store.values.isEmpty)
    }

    @Test func connectingAgainReplacesTheEarlierSignIn() {
        let account = account(FakeTokenStore.connected(storefront: "us"))
        account.load()
        account.markNeedsReauth()
        #expect(account.connect(AppleMusicCredentials(developerToken: "dev-token-fake-2", userToken: "user-token-fake-2", storefront: "vn")))
        #expect(account.status == .connected(storefront: "vn"))
        #expect(account.credentials?.developerToken == "dev-token-fake-2")
        #expect(account.credentials?.userToken == "user-token-fake-2")
    }

    @Test func aStoreThatCannotSaveLeavesNothingBehindAndSaysWhy() {
        store.failsToSave = true
        let account = account()
        #expect(!account.connect(credentials))
        #expect(account.status == .notConnected)
        #expect(store.values.isEmpty)
        #expect(account.problem == AppleMusicAccount.keychainProblem)
    }

    @Test func aSuccessfulConnectClearsTheProblem() {
        let account = account()
        account.problem = "earlier"
        #expect(account.connect(credentials))
        #expect(account.problem == nil)
    }

    // MARK: needs reauth

    @Test func needingASignInAgainStopsAskingAppleButKeepsWhatIsStored() {
        let account = account()
        _ = account.connect(credentials)
        account.markNeedsReauth()
        #expect(account.status == .needsReauth)
        #expect(!account.status.isConnected)
        #expect(store.values.count == 3)
    }

    @Test func aDisconnectedAccountDoesNotNeedASignIn() {
        let account = account()
        account.markNeedsReauth()
        #expect(account.status == .notConnected)
    }

    // MARK: developer token

    @Test func aRefreshedDeveloperTokenIsStoredAndOthersKept() {
        let account = account()
        _ = account.connect(credentials)
        account.replaceDeveloperToken("dev-token-fake-new")
        #expect(account.credentials == AppleMusicCredentials(developerToken: "dev-token-fake-new", userToken: "user-token-fake", storefront: "vn"))
        #expect(account.status == .connected(storefront: "vn"))
    }

    // MARK: storefront

    @Test func aStorefrontTheAccountReportsReplacesTheStoredOneAndTheStatus() {
        let account = account(FakeTokenStore.connected(storefront: "us"))
        account.load()
        #expect(account.replaceStorefront("vn"))
        #expect(account.status == .connected(storefront: "vn"))
        #expect(account.credentials?.storefront == "vn")
        #expect(account.credentials?.developerToken == "dev-token-fake")
        #expect(account.credentials?.userToken == "user-token-fake")
    }

    @Test func replacingTheStorefrontKeepsAStatusThatNeedsASignIn() {
        let tokens = FakeTokenStore.connected(storefront: "us")
        let account = account(tokens)
        account.load()
        account.markNeedsReauth()
        #expect(account.replaceStorefront("vn"))
        #expect(account.status == .needsReauth)
        #expect(tokens.values[.storefront] == "vn")
    }

    @Test func aStoreThatCannotSaveKeepsTheOldStorefront() {
        let tokens = FakeTokenStore.connected(storefront: "us")
        let account = account(tokens)
        account.load()
        tokens.failsToSave = true
        #expect(!account.replaceStorefront("vn"))
        #expect(account.status == .connected(storefront: "us"))
        #expect(tokens.values[.storefront] == "us")
    }

    @Test func replacingTheStorefrontOfADisconnectedAccountDoesNothing() {
        let account = account()
        #expect(!account.replaceStorefront("vn"))
        #expect(account.status == .notConnected)
        #expect(store.values.isEmpty)
    }

    // MARK: disconnect

    @Test func disconnectingDeletesEverythingFromTheStore() {
        let account = account()
        _ = account.connect(credentials)
        account.problem = "something"
        account.disconnect()
        #expect(store.values.isEmpty)
        #expect(account.status == .notConnected)
        #expect(account.credentials == nil)
        #expect(account.problem == nil)
    }

    @Test func disconnectingAfterNeedingASignInDeletesToo() {
        let account = account()
        _ = account.connect(credentials)
        account.markNeedsReauth()
        account.disconnect()
        #expect(store.values.isEmpty)
        #expect(account.status == .notConnected)
    }

    @Test func disconnectingWorksWhateverWasLoaded() {
        let tokens = FakeTokenStore.connected()
        let account = account(tokens)
        account.disconnect()
        #expect(tokens.values.isEmpty)
        account.load()
        #expect(account.status == .notConnected)
    }
}
