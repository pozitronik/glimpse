object ShortcutEditorForm: TShortcutEditorForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Shortcut editor'
  ClientHeight = 211
  ClientWidth = 410
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poOwnerFormCenter
  OnKeyDown = FormKeyDown
  DesignSize = (
    410
    211)
  TextHeight = 15
  object LblAction: TLabel
    Left = 0
    Top = 0
    Width = 410
    Height = 15
    Align = alTop
    Caption = 'Action:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    ExplicitLeft = 16
    ExplicitTop = 14
    ExplicitWidth = 39
  end
  object LblHint: TLabel
    Left = 0
    Top = 155
    Width = 410
    Height = 15
    Align = alTop
    Caption = 'Press a key to add a shortcut (Escape closes the dialog)'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ExplicitLeft = 16
    ExplicitTop = 190
    ExplicitWidth = 288
  end
  object LstChords: TListBox
    Left = 0
    Top = 15
    Width = 410
    Height = 140
    Align = alTop
    ItemHeight = 15
    TabOrder = 0
    OnClick = LstChordsClick
    ExplicitLeft = 16
    ExplicitTop = 16
    ExplicitWidth = 380
  end
  object BtnRemove: TButton
    Left = 0
    Top = 175
    Width = 80
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Remove'
    TabOrder = 1
    OnClick = BtnRemoveClick
  end
  object BtnOK: TButton
    Left = 244
    Top = 176
    Width = 80
    Height = 28
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    ModalResult = 1
    TabOrder = 2
    ExplicitLeft = 214
  end
  object BtnCancel: TButton
    Left = 330
    Top = 175
    Width = 80
    Height = 28
    Anchors = [akRight, akBottom]
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
    ExplicitLeft = 300
  end
end
