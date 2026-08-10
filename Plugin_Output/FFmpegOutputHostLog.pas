unit FFmpegOutputHostLog;

// AviUtl2から渡されたloggerを保持し、ログ障害を出力処理へ波及させずに通知する。

interface

uses
  AviUtl2OutputTypes;

procedure InitializeOutputHostLogger(Logger: PLogHandle);
procedure OutputHostLogInfo(const MessageText: string);
procedure OutputHostLogWarning(const MessageText: string);
procedure OutputHostLogError(const MessageText: string);

implementation

var
  HostLogger: PLogHandle = nil;

procedure InitializeOutputHostLogger(Logger: PLogHandle);
begin
  HostLogger := Logger;
end;

procedure OutputHostLogInfo(const MessageText: string);
begin
  try
    if (HostLogger <> nil) and Assigned(HostLogger^.info) then
      HostLogger^.info(HostLogger, PWideChar(MessageText));
  except
    // ログ出力の失敗でエンコード本体を止めない。
  end;
end;

procedure OutputHostLogWarning(const MessageText: string);
begin
  try
    if (HostLogger <> nil) and Assigned(HostLogger^.warn) then
      HostLogger^.warn(HostLogger, PWideChar(MessageText));
  except
    // ログ出力の失敗でエンコード本体を止めない。
  end;
end;

procedure OutputHostLogError(const MessageText: string);
begin
  try
    if (HostLogger <> nil) and Assigned(HostLogger^.error) then
      HostLogger^.error(HostLogger, PWideChar(MessageText));
  except
    // ログ出力の失敗でエンコード本体を止めない。
  end;
end;

end.
