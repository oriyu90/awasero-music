# 合わせろMusic（awasero-music）

鼻歌を録音し、音同士の関係を保ちながら調とピッチのずれを推定して、編集可能な楽譜・MIDIへ変換するmacOSアプリです。

## 現在動作する機能

- プロジェクト一覧（保存済みプロジェクトを開く・複製・削除）
- 入力機器の選択、BPM・拍子・カウントイン付きメトロノーム、タップでのテンポ入力（TAP/リセット）
- マイク録音、入力レベル表示、無音・クリッピング警告、録音時間上限(5分)、録音の確認再生
- 録音後の基本周波数・発音区間・テンポ解析（キャンセル可能）
- 候補ごとに最適な全体ピッチオフセットを探索する調候補の推定
- 音符・休符への量子化（グリッド・強さ指定、選択音符または全音符に適用）
- ピアノロールと簡易五線譜の表示、複数音符の選択
- 音程、開始位置、長さ、ベロシティの編集、半音単位の移調（⌘↑/⌘↓）、範囲選択によるベロシティ一括設定・クレッシェンド/デクレッシェンド
- 複数テンポポイントの追加・編集、拍範囲を指定したテンポの微調整（MIDI・MusicXML・WAV書き出しに反映）
- 内蔵音色によるメロディ試聴
- 小節単位のコード推定・表示・手動修正（MIDI・MusicXMLへ反映）
- 調号・臨時記号を反映したMusicXML/PDF出力
- 再解析、手動編集の破棄確認、Undo/Redo
- プロジェクトの保存・読込、自動保存・クラッシュ復旧
- MIDI、MusicXML、PDF楽譜、WAV音声の書き出し

録音中のリアルタイム譜面化・MIDI出力、多声解析、DAW同期、内蔵歌声合成、AI楽曲生成は搭載対象ではありません。

今後の課題は[awasero-music.md](./awasero-music.md)にまとめています。

## ビルドと起動

ターミナルで次を実行します。

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open '.build/合わせろMusic.app'
```

開発中は以下でも起動できます。

```sh
swift run --disable-sandbox AwaseroMusic
```

初回録音時にmacOSのマイク許可を求められます。

## 自己診断

```sh
.build/debug/AwaseroMusic --self-check
```

音高変換、調・コード推定、MIDI・MusicXML・WAV出力の基本整合性を確認します。

## テスト

```sh
swift test
```

`XCTest`はフルのXcodeが必要です。コマンドラインツールのみの環境では、事前に`sudo xcode-select -s /Applications/Xcode.app`を実行するか、コマンドの先頭に`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`を付けて実行してください。

## DMGの作成

```sh
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh
```

`.build/合わせろMusic-1.1.0.dmg`とSHA-256チェックサムが生成されます。Apple Developer ID証明書がある場合は、`AWASERO_SIGN_IDENTITY`へ証明書名を設定して実行できます。

```sh
AWASERO_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
AWASERO_NOTARY_PROFILE="awasero-notary" \
./scripts/build-dmg.sh
```

`AWASERO_NOTARY_PROFILE`には、事前に`notarytool store-credentials`でキーチェーンへ保存したプロファイル名を指定します。設定した場合はApple公証への送信とstaple検証まで自動で行います。現在のSwift Packageによる成果物はApple Silicon（arm64）版です。

## ライセンス

Copyright © 2026 Yuki_Orita

本ソフトウェアは[MIT License](./LICENSE)で配布されます。
