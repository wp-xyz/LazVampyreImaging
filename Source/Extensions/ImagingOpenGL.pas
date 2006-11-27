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

{ This unit contains functions for loading and saving OpenGL textures
  using Imaging and for converting images to textures and vice versa.}
unit ImagingOpenGL;

{$I ImagingOptions.inc}

interface

uses
  SysUtils, Classes, ImagingTypes, Imaging, ImagingFormats,
  ImagingUtility, gl, glext{,dglOpenGL};

type
  { Various texture capabilities of installed OpenGL driver.}
  TGLTextureCaps = record
    MaxTextureSize: LongInt;
    PowerOfTwo: Boolean;
    DXTCompression: Boolean;
    FloatTextures: Boolean;
    MaxAnisotropy: LongInt;
    MaxSimultaneousTextures: LongInt;
  end;

{ Returns texture capabilities of installed OpenGL driver.}
function GetGLTextureCaps(var Caps: TGLTextureCaps): Boolean;
{ Function which can be used to retrieve GL extension functions.}
function GetGLProcAddress(const ProcName: string): Pointer;
{ Returns True if the given GL extension is supported.}
function IsGLExtensionSupported(const Extension: string): Boolean;
{ Returns True if the given image format can be represented as GL texture
  format. GLFormat, GLType, and GLInternal are parameters for functions like
  glTexImage. Note that GLU functions like gluBuildMipmaps cannot handle some
  formats returned by this function (i.e. GL_UNSIGNED_SHORT_5_5_5_1 as GLType).
  If you are using compressed or floating-point images make sure that they are
  supported by hardware using GetGLTextureCaps, ImageFormatToGL does not
  check this.}
function ImageFormatToGL(Format: TImageFormat; var GLFormat: GLenum;
  var GLType: GLenum; var GLInternal: GLint): Boolean;

{ All GL textures created by Imaging functions have default parameters set -
  that means that no glTexParameter calls are made so default filtering,
  wrapping, and other parameters are used. Created textures
  are left bound by glBindTexture when function is exited.}

{ Creates GL texture from image in file in format supported by Imaging.}
function LoadGLTextureFromFile(const FileName: string): GLuint;
{ Creates GL texture from image in stream in format supported by Imaging.}
function LoadGLTextureFromStream(Stream: TStream): GLuint;
{ Creates GL texture from image in memory in format supported by Imaging.}
function LoadGLTextureFromMemory(Data: Pointer; Size: LongInt): GLuint;

{ Converts TImageData structure to OpenGL texture.
  Input images is used as main mipmap level and additional requested
  levels are generated from this one. For the details on parameters
  look at CreateGLTextureFromMultiImage function.}
function CreateGLTextureFromImage(const Image: TImageData;
  Width: LongInt = 0; Height: LongInt = 0; MipMaps: Boolean = True;
  OverrideFormat: TImageFormat = ifUnknown): GLuint;
{ Converts images in TDymImageDataArray to one OpenGL texture.
  First image in array is used as main mipmap level and additional images
  are used as subsequent levels. If there is not enough images
  in array missing levels are automatically generated.
  If driver supports only power of two sized textures images are resized.
  OverrideFormat can be used to convert image into specific format before
  it is passed to OpenGL, ifUnknown means no conversion.
  If desired texture format is not supported by hardware default
  A8R8G8B8 format is used instead for color images and ifGray8 is used
  for luminance images. DXTC (S3TC) compressed and floating point textures
  are created if supported by hardware. Width and Height of 0 mean
  use width and height of main image. MipMaps set to True mean build
  all possible levels, False means use only level 0. }
function CreateGLTextureFromMultiImage(const Images: TDynImageDataArray;
  Width: LongInt = 0; Height: LongInt = 0; MipMaps: Boolean = True;
  OverrideFormat: TImageFormat = ifUnknown): GLuint;

{ Saves GL texture to file in one of formats supported by Imaging.
  Saves all present mipmap levels.}
function SaveGLTextureToFile(const FileName: string; const Texture: GLuint): Boolean;
{ Saves GL texture to stream in one of formats supported by Imaging.
  Saves all present mipmap levels.}
function SaveGLTextureToStream(const Ext: string; Stream: TStream; const Texture: GLuint): Boolean;
{ Saves GL texture to memory in one of formats supported by Imaging.
  Saves all present mipmap levels.}
function SaveGLTextureToMemory(const Ext: string; Data: Pointer; var Size: LongInt; const Texture: GLuint): Boolean;

{ Converts main level of the GL texture to TImageData strucrue. OverrideFormat
  can be used to convert output image to the specified format rather
  than use the format taken from GL texture, ifUnknown means no conversion.}
function CreateImageFromGLTexture(const Texture: GLuint;
  var Image: TImageData; OverrideFormat: TImageFormat = ifUnknown): Boolean;
{ Converts GL texture to TDynImageDataArray array of images. You can specify
  how many mipmap levels of the input texture you want to be converted
  (default is all levels). OverrideFormat can be used to convert output images to
  the specified format rather than use the format taken from GL texture,
  ifUnknown means no conversion.}
function CreateMultiImageFromGLTexture(const Texture: GLuint;
  var Images: TDynImageDataArray; MipLevels: LongInt = 0;
  OverrideFormat: TImageFormat = ifUnknown): Boolean;

implementation

const
  // cube map consts
  GL_TEXTURE_BINDING_CUBE_MAP       = $8514;
  GL_TEXTURE_CUBE_MAP_POSITIVE_X    = $8515;
  GL_TEXTURE_CUBE_MAP_NEGATIVE_X    = $8516;
  GL_TEXTURE_CUBE_MAP_POSITIVE_Y    = $8517;
  GL_TEXTURE_CUBE_MAP_NEGATIVE_Y    = $8518;
  GL_TEXTURE_CUBE_MAP_POSITIVE_Z    = $8519;
  GL_TEXTURE_CUBE_MAP_NEGATIVE_Z    = $851A;

  // texture formats
  GL_COLOR_INDEX                    = $1900;
  GL_STENCIL_INDEX                  = $1901;
  GL_DEPTH_COMPONENT                = $1902;
  GL_RED                            = $1903;
  GL_GREEN                          = $1904;
  GL_BLUE                           = $1905;
  GL_ALPHA                          = $1906;
  GL_RGB                            = $1907;
  GL_RGBA                           = $1908;
  GL_LUMINANCE                      = $1909;
  GL_LUMINANCE_ALPHA                = $190A;
  GL_BGR_EXT                        = $80E0;
  GL_BGRA_EXT                       = $80E1;

  // texture internal formats
  GL_ALPHA4                         = $803B;
  GL_ALPHA8                         = $803C;
  GL_ALPHA12                        = $803D;
  GL_ALPHA16                        = $803E;
  GL_LUMINANCE4                     = $803F;
  GL_LUMINANCE8                     = $8040;
  GL_LUMINANCE12                    = $8041;
  GL_LUMINANCE16                    = $8042;
  GL_LUMINANCE4_ALPHA4              = $8043;
  GL_LUMINANCE6_ALPHA2              = $8044;
  GL_LUMINANCE8_ALPHA8              = $8045;
  GL_LUMINANCE12_ALPHA4             = $8046;
  GL_LUMINANCE12_ALPHA12            = $8047;
  GL_LUMINANCE16_ALPHA16            = $8048;
  GL_INTENSITY                      = $8049;
  GL_INTENSITY4                     = $804A;
  GL_INTENSITY8                     = $804B;
  GL_INTENSITY12                    = $804C;
  GL_INTENSITY16                    = $804D;
  GL_R3_G3_B2                       = $2A10;
  GL_RGB4                           = $804F;
  GL_RGB5                           = $8050;
  GL_RGB8                           = $8051;
  GL_RGB10                          = $8052;
  GL_RGB12                          = $8053;
  GL_RGB16                          = $8054;
  GL_RGBA2                          = $8055;
  GL_RGBA4                          = $8056;
  GL_RGB5_A1                        = $8057;
  GL_RGBA8                          = $8058;
  GL_RGB10_A2                       = $8059;
  GL_RGBA12                         = $805A;
  GL_RGBA16                         = $805B;

  // floating point texture formats
  GL_RGBA32F_ARB                    = $8814;
  GL_INTENSITY32F_ARB               = $8817;
  GL_LUMINANCE32F_ARB               = $8818;
  GL_RGBA16F_ARB                    = $881A;
  GL_INTENSITY16F_ARB               = $881D;
  GL_LUMINANCE16F_ARB               = $881E;

  // compressed texture formats
  GL_COMPRESSED_RGBA_S3TC_DXT1_EXT  = $83F1;
  GL_COMPRESSED_RGBA_S3TC_DXT3_EXT  = $83F2;
  GL_COMPRESSED_RGBA_S3TC_DXT5_EXT  = $83F3;

  // various GL extension constants
  GL_MAX_TEXTURE_UNITS              = $84E2;
  GL_TEXTURE_MAX_ANISOTROPY_EXT     = $84FE;
  GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT = $84FF;

  // texture source data formats
  GL_UNSIGNED_BYTE_3_3_2            = $8032;
  GL_UNSIGNED_SHORT_4_4_4_4         = $8033;
  GL_UNSIGNED_SHORT_5_5_5_1         = $8034;
  GL_UNSIGNED_INT_8_8_8_8           = $8035;
  GL_UNSIGNED_INT_10_10_10_2        = $8036;
  GL_UNSIGNED_BYTE_2_3_3_REV        = $8362;
  GL_UNSIGNED_SHORT_5_6_5           = $8363;
  GL_UNSIGNED_SHORT_5_6_5_REV       = $8364;
  GL_UNSIGNED_SHORT_4_4_4_4_REV     = $8365;
  GL_UNSIGNED_SHORT_1_5_5_5_REV     = $8366;
  GL_UNSIGNED_INT_8_8_8_8_REV       = $8367;
  GL_UNSIGNED_INT_2_10_10_10_REV    = $8368;
  GL_HALF_FLOAT_ARB                 = $140B;

{$IFDEF MSWINDOWS}
  GLLibName = 'opengl32.dll';
{$ENDIF}
{$IFDEF UNIX}
  GLLibName = 'libGL.so';
{$ENDIF}

type
  TglCompressedTexImage2D = procedure (Target: GLenum; Level: GLint;
    InternalFormat: GLenum; Width: GLsizei; Height: GLsizei; Border: GLint;
    ImageSize: GLsizei; const Data: PGLvoid);
    {$IFDEF MSWINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
var
  glCompressedTexImage2D: TglCompressedTexImage2D = nil;
  ExtensionBuffer: string = '';

{$IFDEF MSWINDOWS}
function wglGetProcAddress(ProcName: PChar): Pointer; stdcall; external GLLibName;
{$ENDIF}
{$IFDEF UNIX}
function glXGetProcAddress(ProcName: PChar): Pointer; cdecl; external GLLibName;
{$ENDIF}

function IsGLExtensionSupported(const Extension: string): Boolean;
var
  ExtPos: LongInt;
begin
  if ExtensionBuffer = '' then
    ExtensionBuffer := glGetString(GL_EXTENSIONS);

  ExtPos := Pos(Extension, ExtensionBuffer);
  Result := ExtPos > 0;
  if Result then
  begin
    Result := ((ExtPos + Length(Extension) - 1) = Length(ExtensionBuffer)) or
      not (ExtensionBuffer[ExtPos + Length(Extension)] in ['_', 'A'..'Z', 'a'..'z']);
  end;
end;

function GetGLProcAddress(const ProcName: string): Pointer;
begin
{$IFDEF MSWINDOWS}
  Result := wglGetProcAddress(PChar(ProcName));
{$ENDIF}
{$IFDEF UNIX}
  Result := glXGetProcAddress(PChar(ProcName));
{$ENDIF}
end;

function GetGLTextureCaps(var Caps: TGLTextureCaps): Boolean;
begin
  // check DXTC support and load extension functions if necesary
  Caps.DXTCompression := IsGLExtensionSupported('GL_ARB_texture_compression') and
    IsGLExtensionSupported('GL_EXT_texture_compression_s3tc');
  if Caps.DXTCompression then
    glCompressedTexImage2D := GetGLProcAddress('glCompressedTexImage2D');
  Caps.DXTCompression := Caps.DXTCompression and (@glCompressedTexImage2D <> nil);
  // check non power of 2 textures
  Caps.PowerOfTwo := not IsGLExtensionSupported('GL_ARB_texture_non_power_of_two');
  // check for floating point textures support
  Caps.FloatTextures := IsGLExtensionSupported('GL_ARB_texture_float');
  // get max texture size
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, @Caps.MaxTextureSize);
  // get max anisotropy
  if IsGLExtensionSupported('GL_EXT_texture_filter_anisotropic') then
    glGetIntegerv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, @Caps.MaxAnisotropy)
  else
    Caps.MaxAnisotropy := 0;
  // get number of texture units
  if IsGLExtensionSupported('GL_ARB_multitexture') then
    glGetIntegerv(GL_MAX_TEXTURE_UNITS, @Caps.MaxSimultaneousTextures)
  else
    Caps.MaxSimultaneousTextures := 1;
  // get max texture size
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, @Caps.MaxTextureSize);

  Result := True;
end;

function ImageFormatToGL(Format: TImageFormat; var GLFormat: GLenum;
  var GLType: GLenum; var GLInternal: GLint): Boolean;
begin
  GLFormat := 0;
  GLType := 0;
  GLInternal := 0;
  case Format of
    // Gray formats
    ifGray8, ifGray16:
      begin
        GLFormat   := GL_LUMINANCE;
        GLType     := Iff(Format = ifGray8, GL_UNSIGNED_BYTE, GL_UNSIGNED_SHORT);
        GLInternal := Iff(Format = ifGray8, GL_LUMINANCE8, GL_LUMINANCE16);
      end;
    ifA8Gray8, ifA16Gray16:
      begin
        GLFormat   := GL_LUMINANCE_ALPHA;
        GLType     := Iff(Format = ifA8Gray8, GL_UNSIGNED_BYTE, GL_UNSIGNED_SHORT);
        GLInternal := Iff(Format = ifA8Gray8, GL_LUMINANCE8_ALPHA8, GL_LUMINANCE16_ALPHA16);
      end;
    // RGBA formats
    ifR3G3B2:
      begin
        GLFormat   := GL_RGB;
        GLType     := GL_UNSIGNED_BYTE_3_3_2;
        GLInternal := GL_R3_G3_B2;
      end;
    ifR5G6B5:
      begin
        GLFormat   := GL_RGB;
        GLType     := GL_UNSIGNED_SHORT_5_6_5;
        GLInternal := GL_RGB5;
      end;
    ifA1R5G5B5, ifX1R5G5B5:
      begin
        GLFormat   := GL_BGRA_EXT;
        GLType     := GL_UNSIGNED_SHORT_1_5_5_5_REV;
        GLInternal := Iff(Format = ifA1R5G5B5, GL_RGB5_A1, GL_RGB5);
      end;
    ifA4R4G4B4, ifX4R4G4B4:
      begin
        GLFormat   := GL_BGRA_EXT;
        GLType     := GL_UNSIGNED_SHORT_4_4_4_4_REV;
        GLInternal := Iff(Format = ifA4R4G4B4, GL_RGBA4, GL_RGB4);
      end;
    ifR8G8B8:
      begin
        GLFormat   := GL_BGR_EXT;
        GLType     := GL_UNSIGNED_BYTE;
        GLInternal := GL_RGB8;
      end;
    ifA8R8G8B8, ifX8R8G8B8:
      begin
        GLFormat   := GL_BGRA_EXT;
        GLType     := GL_UNSIGNED_BYTE;
        GLInternal := Iff(Format = ifA8R8G8B8, GL_RGBA8, GL_RGB8);
      end;
    ifR16G16B16, ifB16G16R16:
      begin
        GLFormat   := Iff(Format = ifR16G16B16, GL_BGR_EXT, GL_RGB);
        GLType     := GL_UNSIGNED_SHORT;
        GLInternal := GL_RGB16;
      end;
    ifA16R16G16B16, ifA16B16G16R16:
      begin
        GLFormat   := Iff(Format = ifA16R16G16B16, GL_BGRA_EXT, GL_RGBA);
        GLType     := GL_UNSIGNED_SHORT;
        GLInternal := GL_RGBA16;
      end;
    // Floating-Point formats
    ifR32F:
      begin
        GLFormat   := GL_RED;
        GLType     := GL_FLOAT;
        GLInternal := GL_LUMINANCE32F_ARB;
      end;
    ifA32R32G32B32F, ifA32B32G32R32F:
      begin
        GLFormat   := Iff(Format = ifA32R32G32B32F, GL_BGRA_EXT, GL_RGBA);
        GLType     := GL_FLOAT;
        GLInternal := GL_RGBA32F_ARB;
      end;
    ifR16F:
      begin
        GLFormat   := GL_RED;
        GLType     := GL_HALF_FLOAT_ARB;
        GLInternal := GL_LUMINANCE16F_ARB;
      end;
    ifA16R16G16B16F, ifA16B16G16R16F:
      begin
        GLFormat   := Iff(Format = ifA16R16G16B16F, GL_BGRA_EXT, GL_RGBA);
        GLType     := GL_HALF_FLOAT_ARB;
        GLInternal := GL_RGBA16F_ARB;
      end;
    // Special formats
    ifDXT1: GLInternal := GL_COMPRESSED_RGBA_S3TC_DXT1_EXT;
    ifDXT3: GLInternal := GL_COMPRESSED_RGBA_S3TC_DXT3_EXT;
    ifDXT5: GLInternal := GL_COMPRESSED_RGBA_S3TC_DXT5_EXT;
  end;
  Result := GLInternal <> 0;
end;

function LoadGLTextureFromFile(const FileName: string): GLuint;
var
  Images: TDynImageDataArray;
begin
  if LoadMultiImageFromFile(FileName, Images) and (Length(Images) > 0) then
  begin
    Result := CreateGLTextureFromMultiImage(Images, Images[0].Width,
      Images[0].Height, True);
  end
  else
    Result := 0;
  FreeImagesInArray(Images);
end;

function LoadGLTextureFromStream(Stream: TStream): GLuint;
var
  Images: TDynImageDataArray;
begin
  if LoadMultiImageFromStream(Stream, Images) and (Length(Images) > 0) then
  begin
    Result := CreateGLTextureFromMultiImage(Images, Images[0].Width,
      Images[0].Height, True);
  end
  else
    Result := 0;
  FreeImagesInArray(Images);
end;

function LoadGLTextureFromMemory(Data: Pointer; Size: LongInt): GLuint;
var
  Images: TDynImageDataArray;
begin
  if LoadMultiImageFromMemory(Data, Size, Images)  and (Length(Images) > 0) then
  begin
    Result := CreateGLTextureFromMultiImage(Images, Images[0].Width,
      Images[0].Height, True);
  end
  else
    Result := 0;
  FreeImagesInArray(Images);
end;

function CreateGLTextureFromImage(const Image: TImageData;
  Width, Height: LongInt; MipMaps: Boolean; OverrideFormat: TImageFormat): GLuint;
var
  Arr: TDynImageDataArray;
begin
  // Just calls function operating on image arrays
  SetLength(Arr, 1);
  Arr[0] := Image;
  Result := CreateGLTextureFromMultiImage(Arr, Width, Height, MipMaps,
    OverrideFormat);
end;

function CreateGLTextureFromMultiImage(const Images: TDynImageDataArray;
  Width, Height: LongInt; MipMaps: Boolean; OverrideFormat: TImageFormat): GLuint;
var
  I, MipLevels, PossibleLevels, ExistingLevels, CurrentWidth, CurrentHeight: LongInt;
  Caps: TGLTextureCaps;
  GLFormat: GLenum;
  GLType: GLenum;
  GLInternal: GLint;
  Desired, ConvTo: TImageFormat;
  Info: TImageFormatInfo;
  SpecialMipLevel: TImageData;
  LevelsArray: TDynImageDataArray;
  NeedsResize, NeedsConvert: Boolean;
  UnpackAlignment, UnpackSkipRows, UnpackSkipPixels, UnpackRowLength: LongInt;
begin
  Result := 0;
  ExistingLevels := 0;
  if GetGLTextureCaps(Caps) and (Length(Images) > 0) then
  try
    // First check desired size and modify it if necessary
    if Width <= 0 then Width := Images[0].Width;
    if Height <= 0 then Height := Images[0].Height;
    if Caps.PowerOfTwo then
    begin
      // If device supports only power of 2 texture sizes
      Width := NextPow2(Width);
      Height := NextPow2(Height);
    end;
    Width := ClampInt(Width, 1, Caps.MaxTextureSize);
    Height := ClampInt(Height, 1, Caps.MaxTextureSize);

    // Get various mipmap level counts and modify
    // desired MipLevels if its value is invalid
    ExistingLevels := Length(Images);
    PossibleLevels := GetNumMipMapLevels(Width, Height);
    if MipMaps then
      MipLevels := PossibleLevels
    else
      MipLevels := 1;

    // Now determine which image format will be used
    if OverrideFormat = ifUnknown then
      Desired := Images[0].Format
    else
      Desired := OverrideFormat;

    // Check if the hardware supports floating point and compressed textures  
    GetImageFormatInfo(Desired, Info);
    if Info.IsFloatingPoint and not Caps.FloatTextures then
      Desired := ifA8R8G8B8;
    if (Desired in [ifDXT1, ifDXT3, ifDXT5]) and not Caps.DXTCompression then
      Desired := ifA8R8G8B8;

    // Try to find GL format equivalent to image format and if it is not
    // found use one of default formats
    if not ImageFormatToGL(Desired, GLFormat, GLType, GLInternal) then
    begin
      GetImageFormatInfo(Desired, Info);
      if Info.HasGrayChannel then
        ConvTo := ifGray8
      else
        ConvTo := ifA8R8G8B8;
      if not ImageFormatToGL(ConvTo, GLFormat, GLType, GLInternal) then
        Exit;
    end
    else
      ConvTo := Desired;

    // Prepare array for mipmap levels
    SetLength(LevelsArray, MipLevels);

    CurrentWidth := Width;
    CurrentHeight := Height;

    // Store old pixel unpacking settings
    glGetIntegerv(GL_UNPACK_ALIGNMENT, @UnpackAlignment);
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, @UnpackSkipRows);
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, @UnpackSkipPixels);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, @UnpackRowLength);
    // Set new pixel unpacking settings
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);

    // Generate new texture, bind it and set
    glGenTextures(1, @Result);
    glBindTexture(GL_TEXTURE_2D, Result);
    if Byte(glIsTexture(Result)) <> GL_TRUE then
      Exit;

    for I := 0 to MipLevels - 1 do
    begin
      // Check if we can use input image array as a source for this mipmap level
      if I < ExistingLevels then
      begin
        // Check if input image for this mipmap level has the right
        // size and format
        NeedsResize := not ((Images[I].Width = CurrentWidth) and (Images[I].Height = CurrentHeight));
        NeedsConvert := not (Images[I].Format = ConvTo);

        if NeedsResize or NeedsConvert then
        begin
          // Input image must be resized or converted to different format
          // to become valid mipmap level
          CloneImage(Images[I], LevelsArray[I]);
          if NeedsConvert then
            ConvertImage(LevelsArray[I], ConvTo);
          if NeedsResize then
            ResizeImage(LevelsArray[I], CurrentWidth, CurrentHeight, rfBilinear);
        end
        else
          // Input image can be used without any changes
          LevelsArray[I] := Images[I];
      end
      else
      begin
        // This mipmap level is not present in the input image array
        // so we create a new level
        if ConvTo in [ifDXT1, ifDXT3, ifDXT5] then
        begin
          // DXTC format image needs to be decompressed, smaller mip level
          // filled and then compressed
          InitImage(SpecialMipLevel);
          CloneImage(LevelsArray[I - 1], SpecialMipLevel);
          ConvertImage(SpecialMipLevel, ifDefault);
          FillMipMapLevel(SpecialMipLevel, CurrentWidth, CurrentHeight, LevelsArray[I]);
          ConvertImage(LevelsArray[I], ConvTo);
          FreeImage(SpecialMipLevel);
        end
        else
          FillMipMapLevel(LevelsArray[I - 1], CurrentWidth, CurrentHeight, LevelsArray[I]);
      end;

      if ConvTo in [ifDXT1, ifDXT3, ifDXT5] then
      begin
        glCompressedTexImage2D(GL_TEXTURE_2D, I, GLInternal, CurrentWidth,
          CurrentHeight, 0, LevelsArray[I].Size, LevelsArray[I].Bits)
      end
      else
      begin
        glTexImage2D(GL_TEXTURE_2D, I, GLInternal, LevelsArray[I].Width,
          LevelsArray[I].Height, 0, GLFormat, GLType, LevelsArray[I].Bits);
      end;

      // Calculate width and height of the next mipmap level
      CurrentWidth := ClampInt(CurrentWidth div 2, 1, CurrentWidth);
      CurrentHeight := ClampInt(CurrentHeight div 2, 1, CurrentHeight);
    end;

    // Restore old pixel unpacking settings
    glPixelStorei(GL_UNPACK_ALIGNMENT, UnpackAlignment);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, UnpackSkipRows);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, UnpackSkipPixels);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, UnpackRowLength);
  finally
    // Free local image copies
    for I := 0 to Length(LevelsArray) - 1 do
    begin
      if ((I < ExistingLevels) and (LevelsArray[I].Bits <> Images[I].Bits)) or
        (I >= ExistingLevels) then
        FreeImage(LevelsArray[I]);
    end;
  end;
end;

function SaveGLTextureToFile(const FileName: string; const Texture: GLuint): Boolean;
var
  Arr: TDynImageDataArray;
  Fmt: TImageFileFormat;
  IsDDS: Boolean;
begin
  Result := CreateMultiImageFromGLTexture(Texture, Arr);
  if Result then
  begin
    Fmt := FindImageFileFormat(GetFileExt(FileName));
    if Fmt <> nil then
    begin
      IsDDS := SameText(Fmt.Extensions[0], 'dds');
      if IsDDS then
      begin
        PushOptions;
        SetOption(ImagingDDSSaveMipMapCount, Length(Arr));
      end;
      Result := SaveMultiImageToFile(FileName, Arr);
      if IsDDS then
        PopOptions;
    end;
    FreeImagesInArray(Arr);
  end;
end;

function SaveGLTextureToStream(const Ext: string; Stream: TStream; const Texture: GLuint): Boolean;
var
  Arr: TDynImageDataArray;
  Fmt: TImageFileFormat;
  IsDDS: Boolean;
begin
  Result := CreateMultiImageFromGLTexture(Texture, Arr);
  if Result then
  begin
    Fmt := FindImageFileFormat(Ext);
    if Fmt <> nil then
    begin
      IsDDS := SameText(Fmt.Extensions[0], 'dds');
      if IsDDS then
      begin
        PushOptions;
        SetOption(ImagingDDSSaveMipMapCount, Length(Arr));
      end;
      Result := SaveMultiImageToStream(Ext, Stream, Arr);
      if IsDDS then
        PopOptions;
    end;
    FreeImagesInArray(Arr);
  end;
end;

function SaveGLTextureToMemory(const Ext: string; Data: Pointer; var Size: LongInt; const Texture: GLuint): Boolean;
var
  Arr: TDynImageDataArray;
  Fmt: TImageFileFormat;
  IsDDS: Boolean;
begin
  Result := CreateMultiImageFromGLTexture(Texture, Arr);
  if Result then
  begin
    Fmt := FindImageFileFormat(Ext);
    if Fmt <> nil then
    begin
      IsDDS := SameText(Fmt.Extensions[0], 'dds');
      if IsDDS then
      begin
        PushOptions;
        SetOption(ImagingDDSSaveMipMapCount, Length(Arr));
      end;
      Result := SaveMultiImageToMemory(Ext, Data, Size, Arr);
      if IsDDS then
        PopOptions;
    end;
    FreeImagesInArray(Arr);
  end;
end;

function CreateImageFromGLTexture(const Texture: GLuint;
  var Image: TImageData; OverrideFormat: TImageFormat): Boolean;
var
  Arr: TDynImageDataArray;
begin
  // Just calls function operating on image arrays
  FreeImage(Image);
  SetLength(Arr, 1);
  Result := CreateMultiImageFromGLTexture(Texture, Arr, 1, OverrideFormat);
  Image := Arr[0];
end;

function CreateMultiImageFromGLTexture(const Texture: GLuint;
  var Images: TDynImageDataArray; MipLevels: LongInt; OverrideFormat: TImageFormat): Boolean;
var
  I, Width, Height, ExistingLevels: LongInt;
begin
  FreeImagesInArray(Images);
  SetLength(Images, 0);
  Result := False;
  if Byte(glIsTexture(Texture)) = GL_TRUE then
  begin
    // Check if desired mipmap level count is valid
    glBindTexture(GL_TEXTURE_2D, Texture);
    if MipLevels <= 0 then
      MipLevels := GetNumMipMapLevels(Width, Height);
    SetLength(Images, MipLevels);
    ExistingLevels := 0;

    for I := 0 to MipLevels - 1 do
    begin
      // Get the current level size
      glGetTexLevelParameteriv(GL_TEXTURE_2D, I, GL_TEXTURE_WIDTH, @Width);
      glGetTexLevelParameteriv(GL_TEXTURE_2D, I, GL_TEXTURE_HEIGHT, @Height);
      // Break when the mipmap chain is broken
      if (Width = 0) or (Height = 0) then
        Break;
      // Create new image and copy texture data
      NewImage(Width, Height, ifA8R8G8B8, Images[I]);
      glGetTexImage(GL_TEXTURE_2D, I, GL_BGRA_EXT, GL_UNSIGNED_BYTE, Images[I].Bits);
      Inc(ExistingLevels);
    end;
    // Resize mipmap array if necessary
    if MipLevels <> ExistingLevels then
      SetLength(Images, ExistingLevels);
    // Convert images to desired format if set
    if OverrideFormat <> ifUnknown then
      for I := 0 to Length(Images) - 1 do
        ConvertImage(Images[I], OverrideFormat);

    Result := True;
  end;
end;

initialization

{
  File Notes:

  -- TODOS ----------------------------------------------------
    - use internal format of texture in CreateMultiImageFromGLTexture
      not only A8R8G8B8
    - support for cube and 3D maps

  -- 0.19 Changes/Bug Fixes -----------------------------------
    - fixed bug in CreateGLTextureFromMultiImage which caused assert failure
      when creating mipmaps (using FillMipMapLevel) for DXTC formats
    - changed single channel floating point texture formats from
      GL_INTENSITY..._ARB to GL_LUMINANCE..._ARB
    - added support for half float texture formats (GL_RGBA16F_ARB etc.)   

  -- 0.17 Changes/Bug Fixes -----------------------------------
    - filtered mipmap creation
    - more texture caps added
    - fixed memory leaks in SaveGLTextureTo... functions

  -- 0.15 Changes/Bug Fixes -----------------------------------
    - unit created and initial stuff added
}

end.
