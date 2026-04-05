object WcxSettingsForm: TWcxSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse WCX Settings'
  ClientHeight = 440
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object GbxExtraction: TGroupBox
    Left = 8
    Top = 8
    Width = 444
    Height = 80
    Caption = ' Extraction '
    TabOrder = 0
    object LblFrameCount: TLabel
      Left = 12
      Top = 24
      Width = 75
      Height = 15
      Caption = 'Frame count:'
    end
    object LblSkipEdges: TLabel
      Left = 12
      Top = 53
      Width = 62
      Height = 15
      Caption = 'Skip edges:'
    end
    object LblSkipEdgesUnit: TLabel
      Left = 198
      Top = 53
      Width = 11
      Height = 15
      Caption = '%'
    end
    object EdtFrameCount: TEdit
      Left = 130
      Top = 20
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 0
    end
    object UdFrameCount: TUpDown
      Left = 175
      Top = 20
      Width = 17
      Height = 23
      Associate = EdtFrameCount
      Min = 1
      Max = 99
      Thousands = False
      TabOrder = 1
    end
    object EdtSkipEdges: TEdit
      Left = 130
      Top = 49
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdSkipEdges: TUpDown
      Left = 175
      Top = 49
      Width = 17
      Height = 23
      Associate = EdtSkipEdges
      Max = 49
      Thousands = False
      TabOrder = 3
    end
  end
  object GbxOutput: TGroupBox
    Left = 8
    Top = 96
    Width = 444
    Height = 109
    Caption = ' Output '
    TabOrder = 1
    object LblOutputMode: TLabel
      Left = 12
      Top = 24
      Width = 78
      Height = 15
      Caption = 'Output mode:'
    end
    object LblFormat: TLabel
      Left = 12
      Top = 53
      Width = 78
      Height = 15
      Caption = 'Image format:'
    end
    object LblJpegQuality: TLabel
      Left = 12
      Top = 82
      Width = 76
      Height = 15
      Caption = 'JPEG quality:'
    end
    object CbxOutputMode: TComboBox
      Left = 130
      Top = 20
      Width = 150
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = CbxOutputModeChange
      Items.Strings = (
        'Separate frames'
        'Combined image')
    end
    object CbxFormat: TComboBox
      Left = 130
      Top = 49
      Width = 80
      Height = 23
      Style = csDropDownList
      TabOrder = 1
      Items.Strings = (
        'PNG'
        'JPEG')
    end
    object EdtJpegQuality: TEdit
      Left = 130
      Top = 78
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdJpegQuality: TUpDown
      Left = 175
      Top = 78
      Width = 17
      Height = 23
      Associate = EdtJpegQuality
      Min = 1
      Max = 100
      Thousands = False
      TabOrder = 3
    end
  end
  object GbxCombined: TGroupBox
    Left = 8
    Top = 213
    Width = 444
    Height = 109
    Caption = ' Combined image '
    TabOrder = 2
    object LblColumns: TLabel
      Left = 12
      Top = 24
      Width = 100
      Height = 15
      Caption = 'Columns (0=auto):'
    end
    object LblCellGap: TLabel
      Left = 12
      Top = 53
      Width = 72
      Height = 15
      Caption = 'Cell gap (px):'
    end
    object EdtColumns: TEdit
      Left = 130
      Top = 20
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 0
    end
    object UdColumns: TUpDown
      Left = 175
      Top = 20
      Width = 17
      Height = 23
      Associate = EdtColumns
      Max = 20
      Thousands = False
      TabOrder = 1
    end
    object EdtCellGap: TEdit
      Left = 130
      Top = 49
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdCellGap: TUpDown
      Left = 175
      Top = 49
      Width = 17
      Height = 23
      Associate = EdtCellGap
      Max = 20
      Thousands = False
      TabOrder = 3
    end
    object ChkTimestamp: TCheckBox
      Left = 12
      Top = 82
      Width = 200
      Height = 17
      Caption = 'Show timestamps on frames'
      TabOrder = 4
    end
  end
  object LblFFmpegPath: TLabel
    Left = 20
    Top = 335
    Width = 76
    Height = 15
    Caption = 'FFmpeg path:'
  end
  object EdtFFmpegPath: TEdit
    Left = 138
    Top = 331
    Width = 290
    Height = 23
    TabOrder = 3
    TextHint = 'Auto-detect'
  end
  object BtnBrowse: TButton
    Left = 432
    Top = 331
    Width = 20
    Height = 23
    Caption = '...'
    TabOrder = 4
    OnClick = BtnBrowseClick
  end
  object BtnOK: TButton
    Left = 296
    Top = 404
    Width = 75
    Height = 28
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 5
  end
  object BtnCancel: TButton
    Left = 377
    Top = 404
    Width = 75
    Height = 28
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 6
  end
end
