import Testing
@testable import MediaModule

@Suite struct VideoTitleParserTests {
    /// (video title, channel) -> (artist, song), shaped like what Chrome reports for YouTube.
    nonisolated static let cases: [(title: String, channel: String, artist: String, song: String)] = [
        ("Rick Astley - Never Gonna Give You Up (Official Video)", "Rick Astley", "Rick Astley", "Never Gonna Give You Up"),
        ("Adele - Hello (Official Music Video)", "AdeleVEVO", "Adele", "Hello"),
        ("Ed Sheeran - Shape of You [Official Video]", "Ed Sheeran", "Ed Sheeran", "Shape of You"),
        ("Coldplay - Yellow (Lyrics)", "Lyrics Channel", "Coldplay", "Yellow"),
        ("Imagine Dragons - Believer (Lyric Video)", "ImagineDragonsVEVO", "Imagine Dragons", "Believer"),
        ("The Weeknd - Blinding Lights (Official Audio)", "TheWeekndVEVO", "The Weeknd", "Blinding Lights"),
        ("BTS (방탄소년단) 'Dynamite' Official MV", "HYBE LABELS", "HYBE LABELS", "BTS (방탄소년단) 'Dynamite'"),
        ("Taylor Swift – Cardigan (Visualizer)", "Taylor Swift", "Taylor Swift", "Cardigan"),
        ("Queen — Bohemian Rhapsody (Remastered 2011)", "Queen Official", "Queen", "Bohemian Rhapsody (Remastered 2011)"),
        ("Queen – Bohemian Rhapsody (Official Video Remastered)", "Queen Official", "Queen", "Bohemian Rhapsody"),
        ("Daft Punk - Get Lucky (feat. Pharrell Williams) (Official Audio) 4K", "Daft Punk", "Daft Punk", "Get Lucky"),
        ("Drake - One Dance ft. Wizkid & Kyla [HD]", "Drake", "Drake", "One Dance"),
        ("Post Malone - Circles (Live)", "Post Malone", "Post Malone", "Circles"),
        ("Travis Scott - SICKO MODE ft. Drake (Prod. by Hit-Boy)", "TravisScottVEVO", "Travis Scott", "SICKO MODE"),
        ("Blackpink - Kill This Love (M/V)", "BLACKPINK", "Blackpink", "Kill This Love"),
        ("Sơn Tùng M-TP | CHẠY NGAY ĐI | OFFICIAL MUSIC VIDEO", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "CHẠY NGAY ĐI"),
        ("Hòa Minzy - Rời Bỏ | Official MV", "Hòa Minzy Official", "Hòa Minzy", "Rời Bỏ"),
        ("Đen - Đưa Nhau Đi Trốn ft. Linh Cáo (Official MV)", "Đen Vâu", "Đen", "Đưa Nhau Đi Trốn"),
        ("Mỹ Tâm - Đừng Hỏi Em | Lyrics Video", "My Tam Official", "Mỹ Tâm", "Đừng Hỏi Em"),
        ("Em Của Ngày Hôm Qua | OFFICIAL MV | Sơn Tùng M-TP", "Sơn Tùng M-TP", "Sơn Tùng M-TP", "Em Của Ngày Hôm Qua"),
        ("Chúng Ta Của Hiện Tại (Official Music Video)", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "Chúng Ta Của Hiện Tại"),
        ("Lạc Trôi - Lyrics", "Hoàng Thùy Linh Official", "Hoàng Thùy Linh", "Lạc Trôi"),
        ("Shape of You", "Ed Sheeran - Topic", "Ed Sheeran", "Shape of You"),
        ("Hello (Official Video)  4K", "AdeleVEVO", "Adele", "Hello"),
        ("-  - Song", "Chan", "Chan", "Song"),
        // No dash to split on: the pipes separate the song from its artist, a translation and noise.
        ("CHẠY NGAY ĐI | RUN NOW | SƠN TÙNG M-TP | Official Music Video", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "CHẠY NGAY ĐI"),
        ("NƠI NÀY CÓ ANH | HERE WITH ME | SƠN TÙNG M-TP | OFFICIAL MV", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "NƠI NÀY CÓ ANH"),
        ("TÌNH YÊU CHẮP VÁ ｜ LOVE PATCHWORK ｜ MONO ｜ Official MV", "MONO Official", "MONO", "TÌNH YÊU CHẮP VÁ"),
        ("Có Chàng Trai Viết Lên Cây | PHAN MẠNH QUỲNH | OFFICIAL MV", "Phan Mạnh Quỳnh Official", "Phan Mạnh Quỳnh", "Có Chàng Trai Viết Lên Cây"),
        ("Sơn Tùng M-TP | Muộn Rồi Mà Sao Còn (Official Video)", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "Muộn Rồi Mà Sao Còn"),
        ("Nơi Này Có Anh | Lyrics Video", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "Nơi Này Có Anh"),
        ("Chúng Ta Của Sau Này ｜ T.R.I", "T.R.I Official", "T.R.I", "Chúng Ta Của Sau Này"),
        ("Đừng Hỏi Em | MY TAM | Lyrics", "Mỹ Tâm Official", "Mỹ Tâm", "Đừng Hỏi Em"),
        ("Levitating | Dua Lipa | Official Music Video", "Dua Lipa", "Dua Lipa", "Levitating"),
        ("Hello | Adele", "Adele - Topic", "Adele", "Hello"),
        ("Hãy Trao Cho Anh | Official MV", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "Hãy Trao Cho Anh"),
        ("Em Của Ngày Hôm Qua // Sơn Tùng M-TP // Official MV", "Sơn Tùng M-TP Official", "Sơn Tùng M-TP", "Em Của Ngày Hôm Qua"),
        // No segment is the channel: the first one is the song and the channel stays the artist.
        ("Dynamite | BTS | Official MV", "HYBE LABELS", "HYBE LABELS", "Dynamite"),
        ("Waiting For You | MONO | Prod. by Someone", "Channel", "Channel", "Waiting For You"),
    ]

    @Test(arguments: cases)
    func titlesAreCleanedToArtistAndSong(title: String, channel: String, artist: String, song: String) {
        let parsed = VideoTitleParser.parse(title: title, channel: channel)
        #expect(parsed.artist == artist, "artist of \(title)")
        #expect(parsed.title == song, "song of \(title)")
    }

    @Test func aSplitNeedsBothParts() {
        let parsed = VideoTitleParser.parse(title: "Solo - ", channel: "Some Channel")
        #expect(parsed.artist == "Some Channel")
        #expect(parsed.title == "Solo")
    }

    @Test func onlyTheFirstSeparatorSplits() {
        let parsed = VideoTitleParser.parse(title: "Artist - Song - Part 2", channel: "X")
        #expect(parsed.artist == "Artist")
        #expect(parsed.title == "Song - Part 2")
    }

    @Test func aNameThatIsOnlyNoiseSurvives() {
        let parsed = VideoTitleParser.parse(title: "Live", channel: "Band")
        #expect(parsed.title == "Live")
    }

    @Test(arguments: [
        "(Official Video)", "(Official Music Video)", "(Official MV)", "[MV]", "(M/V)", "(Lyrics)", "(Lyric Video)",
        "| Lyrics", "(Audio)", "(Official Audio)", "(Visualizer)", "(Live)", "4K", "HD", "MV", "(Prod. by Someone)",
        "(official video)", "[OFFICIAL MV]", "OFFICIAL MV", "| Lyrics Video", "(Lyrics + Vietsub)", "(Official Video) [4K] | Lyrics",
        "(Official 4K Remaster)", "| Official Video Remastered", "[4K Upgrade]", "(1080p HD)", "(Official Video",
    ])
    func everyKindOfNoiseIsStripped(noise: String) {
        let parsed = VideoTitleParser.parse(title: "Artist - Song \(noise)", channel: "X")
        #expect(parsed.artist == "Artist", "artist with \(noise)")
        #expect(parsed.title == "Song", "song with \(noise)")
    }

    @Test func aTitleWithAnAlbumBehindItIsNotSplitOnItsDash() {
        let parsed = VideoTitleParser.parse(title: "Bohemian Rhapsody - Remastered 2011 (Official Video)", channel: "Queen", splitsOnDash: false)
        #expect(parsed.artist == "Queen")
        #expect(parsed.title == "Bohemian Rhapsody - Remastered 2011")
    }

    @Test func aBracketWithRealWordsInItStays() {
        let parsed = VideoTitleParser.parse(title: "Adele - Hello (Can't Live Without You) [Official Video]", channel: "X")
        #expect(parsed.artist == "Adele")
        #expect(parsed.title == "Hello (Can't Live Without You)")
    }

    @Test func aTitleThatStartsLikeAFeaturingMarkIsStillTheTitle() {
        let parsed = VideoTitleParser.parse(title: "Ft Lauderdale Blues (Official Video)", channel: "Chan")
        #expect(parsed.artist == "Chan")
        #expect(parsed.title == "Ft Lauderdale Blues")
    }

    @Test func whitespaceIsCollapsed() {
        let parsed = VideoTitleParser.parse(title: "  Artist   -   Big   Song  (OFFICIAL   VIDEO) ", channel: "X")
        #expect(parsed.artist == "Artist")
        #expect(parsed.title == "Big Song")
    }

    @Test(arguments: [
        ("Best Songs Mix 2024", 420, true),
        ("Chill Playlist", 200, true),
        ("Lofi 1 hour", 200, true),
        ("Nhạc 1 giờ", 200, true),
        ("Nonstop Vinahey", 200, true),
        ("Tuyển tập nhạc Trịnh", 200, true),
        ("Normal Song", 901, true),
        ("Normal Song", 900, false),
        ("Radio Remix", 200, false),
        ("Mixtape Song", 200, false),
        ("Summer Megamix 2024", 420, true),
        ("Top Mixes", 420, true),
        // A mix is a long track: below six minutes "mix" is part of a song's name, above the cap everything goes.
        ("Little Mix - Black Magic (Official Video)", 210, false),
        ("Avicii - Levels (Original Mix)", 180, false),
        ("Mix It Up", 200, false),
        ("Deep House Mix", 360, false),
        ("Deep House Mix", 361, true),
        ("Mix It Up", 901, true),
        ("Playlist", 200, true),
        ("Non Stop Vinahey", 200, true),
        ("Non-stop Party", 200, true),
        ("Tuyển Tập Nhạc".decomposedStringWithCanonicalMapping, 200, true),
        ("Nhạc 1 Giờ".decomposedStringWithCanonicalMapping, 200, true),
        ("10 Hours of Rain", 200, false),
    ])
    func longTracksAndMixesAreSkipped(title: String, seconds: Int, skipped: Bool) {
        #expect(VideoTitleParser.isLongOrMix(title: title, durationSeconds: seconds) == skipped)
    }
}
