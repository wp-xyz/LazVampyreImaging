{
  $Id$
  Vampyre Imaging Library
  by Marek Mauder 
  http://imaginglib.sourceforge.net

  The contents of this file are used with permission, subject to the Mozilla
  Public License Version 1.1 (the "License"); you may not use this file except
  in compliance with the License. You may obtain a copy of the License at
  http://www.mozilla.org/MPL/MPL-1.1.html

  Software distributed under the License is distributed on an "AS IS" basis,
  WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
  the specific language governing rights and limitations under the License.

  Alternatively, the contents of this file may be used under the terms of the
  GNU Lesser General Public License (the  "LGPL License"), in which case the
  provisions of the LGPL License are applicable instead of those above.
  If you wish to allow use of your version of this file only under the terms
  of the LGPL License and not to allow others to use your version of this file
  under the MPL, indicate your decision by deleting  the provisions above and
  replace  them with the notice and other provisions required by the LGPL
  License.  If you do not delete the provisions above, a recipient may use
  your version of this file under either the MPL or the LGPL License.

  For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html
}

{ This unit contains image format loader/saver for TIFF images.}
unit ImagingTiff;

{$I ImagingOptions.inc}

interface

uses
  SysUtils, Imaging, ImagingTypes, ImagingUtility, ImagingIO, ImagingExtras,
  LibTiffDelphi;

type
  { TIFF (Tag Image File Format) loader/saver class. Uses LibTiff so
    it can handle most types of TIFF files.

    Uses LibTiffDelphi now so it is only usable with Delphi. Native support
    is planned.}
  TTiffFileFormat = class(TImageFileFormat)
  private
    FCompression: Integer;
    FJpegQuality: Integer;
  protected
    procedure Define; override;
    function LoadData(Handle: TImagingHandle; var Images: TDynImageDataArray;
      OnlyFirstLevel: Boolean): Boolean; override;
    function SaveData(Handle: TImagingHandle; const Images: TDynImageDataArray;
      Index: Integer): Boolean; override;
    procedure ConvertToSupported(var Image: TImageData;
      const Info: TImageFormatInfo); override;
  public
    function TestFormat(Handle: TImagingHandle): Boolean; override;
    { Specifies compression scheme used when saving TIFF images. Supported values
      are 0 (Uncompressed), 1 (LZW), 2 (PackBits RLE), 3 (Deflate - ZLib), 4 (JPEG).
      Default is 1 (LZW). Note that not all images can be stored with
      JPEG compression - these images will be saved with default compression if
      JPEG is set.}
    property Compression: Integer read FCompression write FCompression;
    { Controls compression quality when selected TIFF compression is Jpeg.
      It is number in range 1..100. 1 means small/ugly file,
      100 means large/nice file. Accessible trough ImagingTiffJpegQuality option.}
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
  end;

implementation

const
  STiffFormatName = 'Tagged Image File Format';
  STiffMasks      = '*.tif,*.tiff';
  TiffSupportedFormats: TImageFormats = [ifIndex8, ifGray8, ifA8Gray8, 
    ifGray16, ifA16Gray16, ifGray32, ifR8G8B8, ifA8R8G8B8, ifR16G16B16,
    ifA16R16G16B16, ifR32F, ifA32R32G32B32F, ifR16F, ifA16R16G16B16F];
  TiffDefaultCompression = 1;
  TiffDefaultJpegQuality = 90;

const
  TiffBEMagic: TChar4 = 'MM'#0#42;
  TiffLEMagic: TChar4 = 'II'#42#0;

type
  TTiffIOWrapper = record
    IO: TIOFunctions;
    Handle: TImagingHandle;
  end;
  PTiffIOWrapper = ^TTiffIOWrapper;

function TIFFReadProc(Fd: Cardinal; Buffer: Pointer; Size: Integer): Integer; cdecl;
begin
  Result := PTiffIOWrapper(Fd).IO.Read(PTiffIOWrapper(Fd).Handle, Buffer, Size);
end;

function TIFFWriteProc(Fd: Cardinal; Buffer: Pointer; Size: Integer): Integer; cdecl;
begin
  Result := PTiffIOWrapper(Fd).IO.Write(PTiffIOWrapper(Fd).Handle, Buffer, Size);
end;

function TIFFSizeProc(Fd: Cardinal): Cardinal; cdecl;
begin
  Result := ImagingIO.GetInputSize(PTiffIOWrapper(Fd).IO, PTiffIOWrapper(Fd).Handle);
end;

function TIFFSeekProc(Fd: Cardinal; Offset: Cardinal; Where: Integer): Cardinal; cdecl;
const
  SEEK_SET = 0;
  SEEK_CUR = 1;
  SEEK_END = 2;
var
  Mode: TSeekMode;
begin
  if Offset = $FFFFFFFF then
  begin
    Result := $FFFFFFFF;
    Exit;
  end;
  case Where of
    SEEK_SET: Mode := smFromBeginning;
    SEEK_CUR: Mode := smFromCurrent;
    SEEK_END: Mode := smFromEnd;
  else
    Mode := smFromBeginning;
  end;
  Result := PTiffIOWrapper(Fd).IO.Seek(PTiffIOWrapper(Fd).Handle, Offset, Mode);
end;

function  TIFFCloseProc(Fd: Cardinal): Integer; cdecl;
begin
  Result := 0;
end;

function TIFFNoMapProc(Fd: Cardinal; Base: PPointer; Size: PCardinal): Integer; cdecl;
begin
  Result := 0;
end;

procedure TIFFNoUnmapProc(Fd: Cardinal; Base: Pointer; Size: Cardinal); cdecl;
begin
end;

var
  LastError: string = 'None';

procedure TIFFErrorHandler(const A, B: AnsiString);
begin
  LastError := string(A + ': ' + B);
end;

{
  TTiffFileFormat implementation
}

procedure TTiffFileFormat.Define;
begin
  inherited;
  FName := STiffFormatName;
  FCanLoad := True;
  FCanSave := True;
  FIsMultiImageFormat := True;
  FSupportedFormats := TiffSupportedFormats;
  FCompression := TiffDefaultCompression;
  FJpegQuality := TiffDefaultJpegQuality;

  AddMasks(STiffMasks);
  RegisterOption(ImagingTiffCompression, @FCompression);
  RegisterOption(ImagingTiffJpegQuality, @FJpegQuality);
end;

function TTiffFileFormat.LoadData(Handle: TImagingHandle;
  var Images: TDynImageDataArray; OnlyFirstLevel: Boolean): Boolean;
var
  Tiff: PTIFF;
  IOWrapper: TTiffIOWrapper;
  I, Idx, TiffResult, ScanLineSize, NumDirectories: Integer;
  RowsPerStrip: LongWord;
  Orientation, BitsPerSample, SamplesPerPixel, Photometric,
    PlanarConfig, SampleFormat: Word;
  DataFormat: TImageFormat;
  CanAccessScanlines: Boolean;
  Red, Green, Blue: PWordRecArray;

  procedure LoadMetadata(Tiff: PTiff; TiffPage: Integer);
  var
    TiffResUnit: Word;
    XRes, YRes: Single;
    ResUnit: TResolutionUnit;
  begin
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_RESOLUTIONUNIT, @TiffResUnit);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_XRESOLUTION, @XRes);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_YRESOLUTION, @YRes);
    if (TiffResUnit <> RESUNIT_NONE) and (XRes >= 0.1) and (YRes >= 0.1) then
    begin
      ResUnit := ruDpi;
      if TiffResUnit = RESUNIT_CENTIMETER then
        ResUnit := ruDpcm;
      FMetadata.SetPhysicalPixelSize(ResUnit, XRes, YRes, False, TiffPage);
    end;
  end;

begin
  Result := False;
  LibTiffDelphiSetErrorHandler(TIFFErrorHandler);

  // Set up IO wrapper and open TIFF
  IOWrapper.IO := GetIO;
  IOWrapper.Handle := Handle;

  Tiff := TIFFClientOpen('LibTIFF', 'r', Cardinal(@IOWrapper), @TIFFReadProc,
    @TIFFWriteProc, @TIFFSeekProc, @TIFFCloseProc,
    @TIFFSizeProc, @TIFFNoMapProc, @TIFFNoUnmapProc);

  if Tiff <> nil then
    TIFFSetFileNo(Tiff, Cardinal(@IOWrapper))
  else
    Exit;

  NumDirectories := TIFFNumberOfDirectories(Tiff);
  SetLength(Images, NumDirectories);

  for Idx := 0 to NumDirectories - 1 do
  begin
    TIFFSetDirectory(Tiff, Idx);

    // Set defaults for TIFF fields
    DataFormat := ifUnknown;

    // Read some TIFF fields with basic image info
    TIFFGetField(Tiff, TIFFTAG_IMAGEWIDTH, @Images[Idx].Width);
    TIFFGetField(Tiff, TIFFTAG_IMAGELENGTH, @Images[Idx].Height);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_ORIENTATION, @Orientation);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_BITSPERSAMPLE, @BitsPerSample);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_SAMPLESPERPIXEL, @SamplesPerPixel);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_SAMPLEFORMAT, @SampleFormat);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_PHOTOMETRIC, @Photometric);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_PLANARCONFIG, @PlanarConfig);
    TIFFGetFieldDefaulted(Tiff, TIFFTAG_ROWSPERSTRIP, @RowsPerStrip);

    // Load supported metadata
    LoadMetadata(Tiff, Idx);
    // See if we can just copy scanlines from TIFF to Imaging image
    CanAccessScanlines := (PlanarConfig = PLANARCONFIG_CONTIG) or (SamplesPerPixel = 1);

    if CanAccessScanlines then
    begin
      // We can copy scanlines so we try to find data format that best matches
      // TIFFs internal data format
      if Photometric = PHOTOMETRIC_MINISBLACK then
      begin
        if (SampleFormat = SAMPLEFORMAT_UINT) then
        begin
          case BitsPerSample of
             8:
               case SamplesPerPixel of
                 1: DataFormat := ifGray8;
                 2: DataFormat := ifA8Gray8;
               end;
            16:
               case SamplesPerPixel of
                 1: DataFormat := ifGray16;
                 2: DataFormat := ifA16Gray16;
               end;
            32:
               if SamplesPerPixel = 1 then
                 DataFormat := ifGray32;
          end;
        end
        else if (SampleFormat = SAMPLEFORMAT_IEEEFP) then
        begin
          case BitsPerSample of
            16:
               if SamplesPerPixel = 1 then
                 DataFormat := ifR16F;
            32:
               if SamplesPerPixel = 1 then
                 DataFormat := ifR32F;
          end;
        end;
      end
      else if Photometric = PHOTOMETRIC_RGB then
      begin
        if (SampleFormat = SAMPLEFORMAT_UINT) then
        begin
          case BitsPerSample of
             8:
               case SamplesPerPixel of
                 3: DataFormat := ifR8G8B8;
                 4: DataFormat := ifA8R8G8B8;
               end;
            16:
               case SamplesPerPixel of
                 3: DataFormat := ifR16G16B16;
                 4: DataFormat := ifA16R16G16B16;
               end;
          end;
        end
        else if (SampleFormat = SAMPLEFORMAT_IEEEFP) then
        begin
          case BitsPerSample of
            16:
               if SamplesPerPixel = 4 then
                 DataFormat := ifA16R16G16B16F;
            32:
               if SamplesPerPixel = 4 then
                 DataFormat := ifA32R32G32B32F;
          end;
        end;
      end
      else if Photometric = PHOTOMETRIC_PALETTE then
      begin
        if (SamplesPerPixel = 1) and (SampleFormat = SAMPLEFORMAT_UINT) and (BitsPerSample = 8) then
          DataFormat := ifIndex8
      end;
    end;

    if DataFormat = ifUnknown then
    begin
      // Use RGBA interface to read A8R8G8B8 TIFFs and mainly TIFFs in various
      // formats with no Imaging equivalent, exotic color spaces etc.
      NewImage(Images[Idx].Width, Images[Idx].Height, ifA8R8G8B8, Images[Idx]);
      TiffResult := TIFFReadRGBAImageOriented(Tiff, Images[Idx].Width, Images[Idx].Height,
        Images[Idx].Bits, Orientation, 0);
      if TiffResult = 0 then
        RaiseImaging(LastError, []);
    end
    else
    begin
      // Create new image in given format and read scanlines from TIFF,
      // read palette too if needed
      NewImage(Images[Idx].Width, Images[Idx].Height, DataFormat, Images[Idx]);
      ScanLineSize := TIFFScanlineSize(Tiff);

      for I := 0 to Images[Idx].Height - 1 do
        TIFFReadScanline(Tiff, @PByteArray(Images[Idx].Bits)[I * ScanLineSize], I, 0);

      if DataFormat = ifIndex8 then
      begin
        TIFFGetField(Tiff, TIFFTAG_COLORMAP, @Red, @Green, @Blue);
        for I := 0 to 255 do
        with Images[Idx].Palette[I] do
        begin
          A := 255;
          R := Red[I].High;
          G := Green[I].High;
          B := Blue[I].High;
        end;
      end;
    end;

    // TIFF uses BGR order so we must swap it, but not images we got
    // from TiffLib RGBA interface.
    if (Photometric = PHOTOMETRIC_RGB) or (DataFormat = ifUnknown) then
      SwapChannels(Images[Idx], ChannelRed, ChannelBlue);
  end;

  TIFFClose(Tiff);
  Result := True;
end;

function TTiffFileFormat.SaveData(Handle: TImagingHandle;
  const Images: TDynImageDataArray; Index: Integer): Boolean;
const
  Compressions: array[0..4] of Word = (COMPRESSION_NONE, COMPRESSION_LZW,
    COMPRESSION_PACKBITS, COMPRESSION_DEFLATE, COMPRESSION_JPEG);
var
  Tiff: PTIFF;
  IOWrapper: TTiffIOWrapper;
  I, J, ScanLineSize: Integer;
  ImageToSave: TImageData;
  MustBeFreed: Boolean;
  Info: TImageFormatInfo;
  Orientation, BitsPerSample, SamplesPerPixel, Photometric,
    PlanarConfig, SampleFormat, CompressionScheme: Word;
  RowsPerStrip: LongWord;
  Red, Green, Blue: array[Byte] of TWordRec;

  procedure SaveMetadata(Tiff: PTiff; TiffPage: Integer);
  var
    XRes, YRes: Single;
  begin
    XRes := -1;
    YRes := -1;

    // First try to find phys. size for current TIFF page index. If not found then
    // try size for main image (index 0).
    if not FMetadata.GetPhysicalPixelSize(ruDpcm, XRes, YRes, True, TiffPage) then
      FMetadata.GetPhysicalPixelSize(ruDpcm, XRes, YRes, True, 0);

    if (XRes > 0) and (YRes > 0) then
    begin
      TIFFSetField(Tiff, TIFFTAG_RESOLUTIONUNIT, RESUNIT_CENTIMETER);
      TIFFSetField(Tiff, TIFFTAG_XRESOLUTION, XRes);
      TIFFSetField(Tiff, TIFFTAG_YRESOLUTION, YRes);
    end;
  end;

begin
  Result := False;
  LibTiffDelphiSetErrorHandler(TIFFErrorHandler);

  if not (FCompression in [0..4]) then
    FCompression := TiffDefaultCompression;

  // Set up IO wrapper and open TIFF
  IOWrapper.IO := GetIO;
  IOWrapper.Handle := Handle;

  Tiff := TIFFClientOpen('LibTIFF', 'w', Cardinal(@IOWrapper), @TIFFReadProc,
    @TIFFWriteProc, @TIFFSeekProc, @TIFFCloseProc,
    @TIFFSizeProc, @TIFFNoMapProc, @TIFFNoUnmapProc);

  if Tiff <> nil then
    TIFFSetFileNo(Tiff, Cardinal(@IOWrapper))
  else
    Exit;

  for I := FFirstIdx to FLastIdx do
  begin
    if MakeCompatible(Images[I], ImageToSave, MustBeFreed) then
    with GetIO, ImageToSave do
    try
      GetImageFormatInfo(Format, Info);

      // Set Tag values
      Orientation := ORIENTATION_TOPLEFT;
      BitsPerSample := Info.BytesPerPixel div Info.ChannelCount * 8;
      SamplesPerPixel := Info.ChannelCount;
      SampleFormat := Iff(not Info.IsFloatingPoint, SAMPLEFORMAT_UINT, SAMPLEFORMAT_IEEEFP);
      PlanarConfig := PLANARCONFIG_CONTIG;
      CompressionScheme := Compressions[FCompression];
      if (CompressionScheme = COMPRESSION_JPEG) and ((BitsPerSample <> 8) or
        not (SamplesPerPixel in [1, 3]) or Info.IsIndexed or Info.IsFloatingPoint) then
      begin
        // JPEG compression only for some data formats
        CompressionScheme := Compressions[TiffDefaultCompression];
      end;
      RowsPerStrip := TIFFDefaultStripSize(Tiff, Height);
      if Info.IsIndexed then
        Photometric := PHOTOMETRIC_PALETTE
      else if (Info.HasGrayChannel) or (Info.ChannelCount = 1) then
        Photometric := PHOTOMETRIC_MINISBLACK
      else
        Photometric := PHOTOMETRIC_RGB;

      // Write tags
      TIFFSetField(Tiff, TIFFTAG_IMAGEWIDTH, Width);
      TIFFSetField(Tiff, TIFFTAG_IMAGELENGTH, Height);
      TIFFSetField(Tiff, TIFFTAG_PHOTOMETRIC, Photometric);
      TIFFSetField(Tiff, TIFFTAG_PLANARCONFIG, PlanarConfig);
      TIFFSetField(Tiff, TIFFTAG_ORIENTATION, Orientation);
      TIFFSetField(Tiff, TIFFTAG_BITSPERSAMPLE, BitsPerSample);
      TIFFSetField(Tiff, TIFFTAG_SAMPLESPERPIXEL, SamplesPerPixel);
      TIFFSetField(Tiff, TIFFTAG_SAMPLEFORMAT, SampleFormat);
      TIFFSetField(Tiff, TIFFTAG_COMPRESSION, CompressionScheme);
      if CompressionScheme = COMPRESSION_JPEG then
        TIFFSetField(Tiff, TIFFTAG_JPEGQUALITY, FJpegQuality);
      TIFFSetField(Tiff, TIFFTAG_ROWSPERSTRIP, RowsPerStrip);
      // Save supported metadata
      SaveMetadata(Tiff, I);

      if Format = ifIndex8 then
      begin
        // Set paletee for indexed images
        for J := 0 to 255 do
        with ImageToSave.Palette[J] do
        begin
          Red[J].High := R;
          Green[J].High := G;
          Blue[J].High := B;
        end;
        TIFFSetField(Tiff, TIFFTAG_COLORMAP, Red, Green, Blue);
      end;

      ScanLineSize := Width * Info.BytesPerPixel;

      if Photometric = PHOTOMETRIC_RGB then
        SwapChannels(ImageToSave, ChannelRed, ChannelBlue);
      // Write image scanlines and then directory for current image
      for J := 0 to Height - 1 do
        TIFFWriteScanline(Tiff, @PByteArray(Bits)[J * ScanLineSize], J, 0);
      if Info.ChannelCount > 1 then
        SwapChannels(ImageToSave, ChannelRed, ChannelBlue);

      TIFFWriteDirectory(Tiff);
    finally
      if MustBeFreed then
        FreeImage(ImageToSave);
    end;
  end;

  TIFFClose(Tiff);
  Result := True;
end;

procedure TTiffFileFormat.ConvertToSupported(var Image: TImageData;
  const Info: TImageFormatInfo);
var
  ConvFormat: TImageFormat;
begin
  if Info.RBSwapFormat in GetSupportedFormats then
    ConvFormat := Info.RBSwapFormat
  else if Info.IsFloatingPoint then
    ConvFormat :=  IffFormat(Info.ChannelCount = 1, ifR32F, ifA32R32G32B32F)
  else if Info.HasGrayChannel then
    ConvFormat := IffFormat(Info.HasAlphaChannel, ifA16Gray16, ifGray32)
  else
    ConvFormat := IffFormat(Info.HasAlphaChannel, ifA8R8G8B8, ifR8G8B8);

  ConvertImage(Image, ConvFormat);
end;

function TTiffFileFormat.TestFormat(Handle: TImagingHandle): Boolean;
var
  Magic: TChar4;
  ReadCount: LongInt;
begin
  Result := False;
  if Handle <> nil then
  begin
    ReadCount := GetIO.Read(Handle, @Magic, SizeOf(Magic));
    GetIO.Seek(Handle, -ReadCount, smFromCurrent);
    Result := (ReadCount >= SizeOf(Magic)) and
      ((Magic = TiffBEMagic) or (Magic = TiffLEMagic));
  end;
end;

initialization
  RegisterImageFileFormat(TTiffFileFormat);

{
  File Notes:

  -- TODOS ----------------------------------------------------
    - nothing now

  -- 0.26.5 Changes/Bug Fixes ---------------------------------
    - Loading and saving of physical resolution metadata.
    - Unicode compatibility fixes in LibTiffDelphi.
    - Added Jpeg compression quality setting.

  -- 0.24.3 Changes/Bug Fixes ---------------------------------
    - Fixed bug in loading and saving of 2 channel images - Imaging
      tried to swap R and B channels here.

  -- 0.23 Changes/Bug Fixes -----------------------------------
    - Added TIFF loading and saving.
    - Unit created and initial code added.
}

end.
