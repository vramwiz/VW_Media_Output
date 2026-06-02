# VW_Media_Input 引き継ぎメモ

## 目的

`VW_Media_Input` は AviUtl2 用の入力プラグインとして、FFmpeg 8.1 系 DLL を使って動画/音声ファイルを読み込むための開発場所。

入力プラグインの土台として、`D:\DelphiProg\test\Syncroh2` の `Syncroh2_Input_Base.dpr` と関連ユニットをコピーして作成した。

プロジェクト名:

- `VW_Media_Input`

開発フォルダ:

- `D:\DelphiProg\test\VW_Media_Input`

## コピー元

入力プラグインの基本構造:

- `D:\DelphiProg\test\Syncroh2\Syncroh2_Input_Base.dpr`
- `D:\DelphiProg\test\Syncroh2\Syncroh2_Input_Base.dproj`
- `Plugin_Input\PluginInputBase.pas`
- `AviUtl\Input\AviUtl2InputTypes.pas`

FFmpeg 検証コード:

- `D:\DelphiProg\test\FFmpeg\04\FFmpegDecoder.pas`

FFmpeg 8.1 系 DLL:

- `avutil-60.dll`
- `avcodec-62.dll`
- `avformat-62.dll`
- `swscale-9.dll`
- `swresample-6.dll`

## 現在の状態

2026-06-02 時点:

- `VW_Media_Input.dpr` / `VW_Media_Input.dproj` を作成済み。
- `Syncroh2_Input_Base` 由来のプロジェクト名を `VW_Media_Input` に置換済み。
- `Plugin_Input\FFmpegDecoder.pas` はコピー済みだが、入力プラグイン処理にはまだ接続していない。
- Win64 Debug ビルド成功。
  - 警告 1
  - エラー 0
  - 警告は `PluginInputBase.pas` の元ベース由来。

現在のプラグイン実装は、まだ `Syncroh2_Input_Base` のダミー入力に近い。

- `PluginInputOpen` は FFmpeg で実ファイルを開いていない。
- ファイル名からサイズ、時間、fps を読む旧テスト処理が残っている。
- `PluginInputReadVideo` は実動画デコードをしていない。
- `func_read_audio` は `0` を返すだけ。
- `INPUT_PLUGIN_FLAG_AUDIO` / `INPUT_INFO_FLAG_AUDIO` はまだ使っていない。

## ビルド方法

Delphi 37.0 の環境変数を読み込んでから MSBuild で Win64 Debug をビルドする。

PowerShell から実行する場合:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

cmd から実行する場合:

```bat
"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

2026-06-02 時点では、この手順で Win64 Debug ビルド成功。

- 警告 0
- エラー 0
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Input` へ `.aui2` と FFmpeg DLL をコピーする。

## 現在のファイルフィルター

現状のフィルターは動画系に加えて音声系を含めている。
動画ファイルの手元サンプルが少ないため、追加分は FFmpeg に渡す仮対応として一通り入れている。

- `*.mp4`
- `*.mov`
- `*.mkv`
- `*.avi`
- `*.wmv`
- `*.asf`
- `*.webm`
- `*.mpg`
- `*.mpeg`
- `*.m2ts`
- `*.ts`
- `*.m4v`
- `*.mp3`
- `*.wav`
- `*.m4a`
- `*.aac`
- `*.wma`
- `*.flac`
- `*.ogg`
- `*.opus`

注意:

- 動画ファイルは FFmpeg 経由で映像情報、映像フレーム、音声情報を返す。
- `*.wmv` / `*.asf` / `*.webm` / `*.mpg` / `*.mpeg` / `*.m2ts` / `*.ts` / `*.m4v` はフィルター追加による仮対応で、実ファイル確認は未実施。
- `*.mp3` / `*.wav` / `*.m4a` / `*.aac` / `*.wma` / `*.flac` / `*.ogg` / `*.opus` は音声専用入力として扱い、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` 経路で PCM16 stereo 48kHz を返す。
- スピーカーが無いため mp3 の聴感確認は未実施だが、AviUtl2 上では問題ないように見える。

## 将来対応

まずは動画ファイル対応を優先する。

段階案:

1. `PluginInputOpen` で `TFFmpegDecoder.Open` を呼び、動画情報を取得する。
2. `PluginInputGetInfo` に幅、高さ、fps、フレーム数、画像フォーマットを設定する。
3. `PluginInputReadVideo` で指定フレームをデコードして AviUtl2 のバッファへ返す。
4. Bitmap 依存を減らし、AviUtl2 が要求する生バッファへ直接書く方向に寄せる。
5. その後、音声付き動画の `func_read_audio` 対応を検討する。

mp3 について:

- FFmpeg 経由で音声専用入力として対応済み。
- 映像ストリームが無い場合でも、音声ストリームが開ければ `TFFmpegDecoder.Open` は成功する。
- 音声のみなので `INPUT_INFO_FLAG_VIDEO` と `BITMAPINFOHEADER` は返さず、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` を使う。
- スピーカーが無いため聴感確認は未実施。波形/メーターなどでの確認は今後行う。

音声形式について:

- `*.wav` / `*.m4a` / `*.aac` / `*.wma` / `*.flac` / `*.ogg` / `*.opus` をフィルターへ追加済み。
- 基本的には mp3 と同じ音声専用入力経路で扱う。
- FFmpeg が開ける音声ストリームなら PCM16 stereo 48kHz として返せる可能性が高い。
- `*.wav` は AviUtl2 標準入力で扱える可能性が高いため、`VW_Media_Input.dpr` の `MEDIA_FILE_FILTER` 定数でコメント切り替えできるようにしている。
  - `MEDIA_FILE_FILTER_WITH_WAV`: wav も FFmpeg 経由で扱う。
  - `MEDIA_FILE_FILTER_WITHOUT_WAV`: wav はこのプラグインのフィルターから外し、標準入力へ任せる。
- 実ファイル確認は今後行う。

## FFmpeg 04 からの注意

`D:\DelphiProg\test\FFmpeg\04` では、FFmpeg 8.1 移行と負荷測定を実施済み。

分かったこと:

- 音声デコード負荷は小さい。
- 主な負荷は FFmpeg の映像デコード本体。
- `sws_scale + TBitmap` 変換も平均数 ms 程度の負荷がある。
- `ImagePreview` への表示コピーは大きな負荷ではなかった。

現在コピーした `Plugin_Input\FFmpegDecoder.pas` は、負荷測定のため一時的にコメントアウトされた箇所を含む可能性がある。

通常の映像表示/変換へ戻す場合は、以下を確認する。

- `Plugin_Input\FFmpegDecoder.pas` の `CopyFrameToBitmap(Frame, Bitmap)` 呼び出し
- `Unit9.pas` 側の `ImagePreview.Picture.Bitmap.Assign(Bitmap)` はこのプラグインには不要

プラグインでは `TBitmap` 表示ではなく、最終的には AviUtl2 の `buf` へ直接出力する設計を目指す。

## 現在のユニット構成

2026-06-02 時点の主なユニット構成:

### 入口

- `VW_Media_Input.dpr`
  - AviUtl2 入力プラグインの exported function を持つ。
  - `PluginInputBase.pas` の関数へ処理を委譲する。

### AviUtl2 入力プラグイン側

- `Plugin_Input\PluginInputBase.pas`
  - AviUtl2 から呼ばれる入力処理本体。
  - `PluginInputOpen` / `PluginInputGetInfo` / `PluginInputReadVideo` / `PluginInputReadAudio` を実装する。
  - 映像は `TFFmpegDecoder` へ委譲する。
  - 音声は `TPluginAudioInputReader` へ委譲する。
  - AviUtl2 へ返すフレームキャッシュ、BITMAPINFOHEADER、フレーム番号管理を持つ。

- `Plugin_Input\PluginAudioInputReader.pas`
  - AviUtl2 の `func_read_audio` 用の読み取り処理。
  - 音声用に別の `TFFmpegDecoder` を開き、PCM16 stereo 48kHz を必要分だけ順次デコードする。
  - `WAVEFORMATEX`、PCM キャッシュ、デコード済みサンプル数を管理する。

### FFmpeg デコーダ本体

- `Plugin_Input\FFmpegDecoder.pas`
  - FFmpeg デコードの中心ユニット。
  - ファイル open / close、映像デコード、音声デコード、シーク、順方向読み取りを担当する。
  - FFmpeg の低レベル API 定義、型定義、フレーム変換、統計計算は別ユニットへ分離済み。
  - 今後肥大化しやすいので、追加機能はできるだけ `Plugin_Input\FFmpeg*.pas` に逃がす方針。

### FFmpeg 周辺ユニット

- `Plugin_Input\FFmpegApi.pas`
  - FFmpeg の record / pointer 型、定数、関数ポインタ型を定義する。
  - FFmpeg DLL のロード、関数取得、`TFFmpegApi.EnsureLoaded`、`ErrorText` を持つ。
  - `RationalToDouble`、`StreamAt`、`StreamTimestampToMs` などの低レベル補助関数もここに置く。

- `Plugin_Input\FFmpegDecoderTypes.pas`
  - デコーダ公開情報と統計用の型定義。
  - `TVideoInfo`、`TAudioInfo`、`TAudioPlaybackStats`、`TDecodeLoadStats`、`TAudioWaveBuffer` を持つ。

- `Plugin_Input\FFmpegFrameConvert.pas`
  - `AVFrame` から出力バッファへの変換処理。
  - `CopyFrameToBgrx32Buffer` は AviUtl2 の 32bit BGRx バッファへ直接書き込む。
  - `CopyFrameToBitmap` は一時確認用/互換用の `TBitmap` 変換。

- `Plugin_Input\FFmpegStreamInfo.pas`
  - ストリーム情報読み取り。
  - 現在は音声ストリーム情報を `TVideoInfo.Audio` に反映する `ReadAudioInfo` を持つ。

- `Plugin_Input\FFmpegDecodeStats.pas`
  - 映像/音声の負荷統計と、PCM 音量確認用統計の計算。
  - `Plugin_Input\FFmpegDecoder.pas` 側は統計 record を持ち、このユニットの関数へ更新処理を委譲する。

### AviUtl2 型ユニット

- `AviUtl\Input\AviUtl2InputTypes.pas`
  - AviUtl2 入力プラグイン用の構造体、フラグ、関数型。

- `AviUtl2InputTypes.pas` 以外の `AviUtl` 配下ユニットと `Lib` 配下ユニットは未使用確認後に削除済み。

### 分割方針

- `Plugin_Input\FFmpegDecoder.pas` には「開く、閉じる、読む、シークする」というデコードの流れを残す。
- FFmpeg API 定義や DLL ロードは `FFmpegApi.pas` に置く。
- AviUtl2 側の都合は `PluginInputBase.pas` / `PluginAudioInputReader.pas` に寄せる。
- 変換、統計、ストリーム情報などの純粋な補助処理は `Plugin_Input\FFmpeg*.pas` へ分ける。
- 新しくまとまった責務が増えた場合は、ルートではなく `Plugin_Input` 配下へ新規ユニットを作る。

## 2026-06-02 mp3 対応状況

mp3 対応の入口を追加した。

変更内容:

- `VW_Media_Input.dpr`
  - プラグイン名を `動画/音声入力` に変更。
  - ファイルフィルターに `*.mp3` を追加。
  - 情報文言を動画/音声向けに変更。
- `Plugin_Input\FFmpegDecoder.pas`
  - 映像ストリームが無いファイルでも、音声ストリームが開ければ `Open` 成功にするよう変更。
  - mp3 のような音声専用入力では、映像デコーダを作らず音声デコーダだけを開く。
- `Plugin_Input\PluginInputBase.pas`
  - `HasVideo` を追加。
  - 音声専用ファイルでは `INPUT_INFO_FLAG_VIDEO` と `BITMAPINFOHEADER` を返さず、`INPUT_INFO_FLAG_AUDIO` / `audio_format` / `audio_n` だけ返す。
  - `PluginInputReadVideo` は映像が無い場合 `0` を返す。
  - `PluginInputReadAudio` は既存の `TPluginAudioInputReader` 経由で PCM16 stereo 48kHz を返す。

ビルド確認:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

結果:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` と FFmpeg DLL を配置済み。

動作確認メモ:

- スピーカーが無いため、実際に音が鳴るかの聴感確認は未実施。
- ただし AviUtl2 上では問題ないように見える。
- 現時点では「mp3 を音声専用入力として開き、音声情報と PCM 読み出し経路を返す」ところまで対応済みと見る。

今後確認したいこと:

- スピーカーまたは波形/メーターで、実際に音声が正しく読めているか確認する。
- 長い mp3 でシークやランダムアクセス要求が来た場合の挙動を確認する。
- 必要なら `func_read_audio` の要求位置が戻るケースに備えて、音声デコードキャッシュ/再オープン/シーク対応を強化する。

## 2026-06-02 リリース用 zip

Win64 Debug ビルド後に、AviUtl2 へ配置済みのプラグインフォルダを zip 化した。
zip 作成処理は `Setup\make_release_zip.bat` にバッチ化した。

作成元:

- `C:\ProgramData\aviutl2\Plugin\VW_Media_Input`

作成先:

- `D:\DelphiProg\test\VW_Media_Input\Setup\VW_Media_Input.zip`

GitHub Releases:

- `https://github.com/vramwiz/VW_Media_Input/releases/tag/v1.0.0`

作成コマンド:

```bat
Setup\make_release_zip.bat
```

zip 内容:

- `VW_Media_Input\VW_Media_Input.aui2`
- `VW_Media_Input\avutil-60.dll`
- `VW_Media_Input\avcodec-62.dll`
- `VW_Media_Input\avformat-62.dll`
- `VW_Media_Input\swscale-9.dll`
- `VW_Media_Input\swresample-6.dll`

メモ:

- zip は `VW_Media_Input` フォルダごと含めている。
- zip ファイル名は日付を付けず、常に `VW_Media_Input.zip` とする。
- 展開先は `C:\ProgramData\aviutl2\Plugin\VW_Media_Input` を想定する。
- zip の配置場所は `releases` ではなく `Setup` フォルダとする。
- 現時点の zip は Debug ビルド由来。正式配布時は Release ビルドで作り直すか検討する。

