object FFmpegSetupForm: TFFmpegSetupForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  BorderWidth = 4
  Caption = 'VideoThumb'
  ClientHeight = 92
  ClientWidth = 354
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Padding.Left = 10
  Padding.Top = 10
  Padding.Right = 10
  Padding.Bottom = 10
  Position = poScreenCenter
  DesignSize = (
    354
    92)
  TextHeight = 15
  object LblTitle: TLabel
    Left = 1
    Top = 8
    Width = 183
    Height = 17
    Caption = 'VideoThumb requires ffmpeg'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LblMsg: TLabel
    Left = 1
    Top = 31
    Width = 200
    Height = 15
    Caption = 'ffmpeg was not found on this system.'
  end
  object BtnBrowse: TButton
    Left = 1
    Top = 62
    Width = 230
    Height = 28
    Caption = 'Browse for ffmpeg.exe...'
    TabOrder = 0
    OnClick = BtnBrowseClick
  end
  object BtnCancel: TButton
    Left = 250
    Top = 62
    Width = 101
    Height = 28
    Anchors = [akTop, akRight]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 1
    ExplicitLeft = 298
  end
end
