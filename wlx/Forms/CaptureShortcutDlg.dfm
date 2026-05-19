object ShortcutEditorForm: TShortcutEditorForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  BorderWidth = 4
  Caption = 'Shortcut editor'
  ClientHeight = 210
  ClientWidth = 400
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
    400
    210)
  TextHeight = 15
  object LblAction: TLabel
    Left = 0
    Top = 0
    Width = 400
    Height = 15
    Align = alTop
    Caption = 'Action:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    ExplicitWidth = 39
  end
  object LblHint: TLabel
    Left = 0
    Top = 155
    Width = 400
    Height = 15
    Align = alTop
    Caption = 'Press a key to add a shortcut'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ExplicitWidth = 150
  end
  object LstChords: TListBox
    Left = 0
    Top = 15
    Width = 400
    Height = 140
    Align = alTop
    ItemHeight = 15
    TabOrder = 0
    OnClick = LstChordsClick
  end
  object BtnRemove: TButton
    Left = 0
    Top = 181
    Width = 80
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Remove'
    TabOrder = 1
    OnClick = BtnRemoveClick
  end
  object BtnOK: TButton
    Left = 234
    Top = 181
    Width = 80
    Height = 28
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    ModalResult = 1
    TabOrder = 2
  end
  object BtnCancel: TButton
    Left = 320
    Top = 181
    Width = 80
    Height = 28
    Anchors = [akRight, akBottom]
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
end
