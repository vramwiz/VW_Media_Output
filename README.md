# VW_Media_Output

VW_Media_Output は、AviUtl2 用の出力プラグインを開発するためのプロジェクトです。

現在は `VW_Media_Input` からコピーしたプロジェクトを、出力プラグイン開発用の骨格へ切り替えた段階です。実際の動画/音声書き出し処理はまだ実装していません。

## 現在の状態

- Delphi ライブラリ名: `VW_Media_Output`
- プロジェクトファイル: `VW_Media_Output.dproj`
- 出力プラグインファイル: `VW_Media_Output.auo2`
- AviUtl2 へ公開する関数: `GetOutputPluginTable`
- 出力プラグイン型定義: `AviUtl\Output\AviUtl2OutputTypes.pas`

## ビルド

```text
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Output.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

ビルド後は `VW_Media_Output.dll` を `VW_Media_Output.auo2` にコピーし、配置先の DLL/RSM を削除する設定です。

## 配置先

```text
C:\ProgramData\aviutl2\Plugin\VW_Media_Output
```

## リリース zip

クローン先で FFmpeg DLL と `VW_Media_Output.auo2` を取得できるように、配置済みフォルダからリリース zip を作成します。

```text
Setup\make_release_zip.bat
```

作成されるファイル:

```text
Setup\VW_Media_Output.zip
```

zip には `VW_Media_Output` フォルダごと含めます。展開後は次の形で配置します。

```text
C:\ProgramData\aviutl2\Plugin\VW_Media_Output
```

## 次に実装するもの

- `func_output` で `POutputInfo` から映像/音声を取得する
- 取得したフレームと音声を FFmpeg などのエンコーダへ渡す
- 出力設定ダイアログと設定保存を追加する
- 対応拡張子のフィルターを実装内容に合わせて調整する

## ライセンス

このプロジェクトは GNU General Public License v3.0 で公開しています。

- [LICENSE](LICENSE)
