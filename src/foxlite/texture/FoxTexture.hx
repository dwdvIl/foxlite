package foxlite.texture;

import foxlite.FoxLog;
import StringTools;
import haxe.crypto.Base64;
import haxe.io.Path;
import haxe.io.BytesInput;

import lime.utils.Assets;
import lime.graphics.opengl.GL;
import lime.graphics.Image;
import lime.system.ThreadPool;
import lime.utils.Bytes;
import lime.utils.UInt8Array;
import lime.utils.ArrayBufferView;

import foxlite.FoxCache;
import foxlite.loaders.FoxLoaderUtil;
import foxlite.renderer.FoxRenderer;
import foxlite.texture.FoxMipFilter;
import foxlite.texture.FoxTextureFilter;
import foxlite.texture.FoxWrapMode;
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.TextureBase;
import openfl.display3D.textures.RectangleTexture;


typedef FoxTextureParams = {
	?wrapMode:FoxWrapMode, 
	?filter:FoxTextureFilter, 
	?mipFilter:FoxMipFilter
}

typedef DDSMipData = {
	width:Int,
	height:Int,
	buffer:ArrayBufferView
}

// DXGI texture formats for DX10+ (EXT_texture_compression_bptc)
#if !foxlite_polymod abstract #else class #end DXGIFormat #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final BC1_UNORM = 71;
	public inline static final BC1_UNORM_SRGB = 72;
	public inline static final BC2_UNORM = 74;
	public inline static final BC2_UNORM_SRGB = 75;
	public inline static final BC3_UNORM = 77;
	public inline static final BC3_UNORM_SRGB = 78;
	public inline static final BC4_UNORM = 80;
	public inline static final BC4_SNORM = 81;
	public inline static final BC5_UNORM = 83;
	public inline static final BC5_SNORM = 84;
	public inline static final BC6H_UF16 = 95;
	public inline static final BC6H_SF16 = 96;
	public inline static final BC7_UNORM = 98;
	public inline static final BC7_UNORM_SRGB = 99;
}

class FoxTexture {
	public var context:Context3D = null;

	public var wrapMode(default, set):FoxWrapMode;
	public var filter(default, set):FoxTextureFilter;
	public var mipFilter(default, set):FoxMipFilter;
	public var glTexture:TextureBase; // Fix C++ black textures via downcast
	public var assetsKey:String;

	/**
		Wheter or not this texture is loaded

		This property also indicates wheter this texture has a valid `glTexture`,
		usually assigned when images load
	**/
	public var loaded(get, never):Bool;

	function get_loaded():Bool {
		return glTexture != null;
	}

	public var width(get, default):Int;
	public var height(get, default):Int;

	public var __paramsNeedUpdate:Bool = true;

	private function set_wrapMode(v:FoxWrapMode):FoxWrapMode {
		if(this.wrapMode == v) return v;
		__paramsNeedUpdate = true;
		return this.wrapMode = v;
	}

	private function set_filter(v:FoxTextureFilter):FoxTextureFilter {
		if(this.filter == v) return v;
		__paramsNeedUpdate = true;
		return this.filter = v;
	}

	private function set_mipFilter(v:FoxMipFilter):FoxMipFilter {
		if(this.mipFilter == v) return v;
		__paramsNeedUpdate = true;
		return this.mipFilter = v;
	}

	private function get_width():Int {
		return glTexture?.__width ?? 0;
	}

	private function get_height():Int {
		return glTexture?.__height ?? 0;
	}

	// Used to store information when resizing
	// If the texture was loaded from a file, it cannot be resized
	private var __format:String = null;
	private var __type:String = null;

	public function new(wrapMode:FoxWrapMode=#if !foxlite_polymod FoxWrapMode.CLAMP #else 0 #end, filter:FoxTextureFilter=#if !foxlite_polymod FoxTextureFilter.LINEAR #else 4 #end, mipFilter:FoxMipFilter=#if !foxlite_polymod FoxMipFilter.MIPNONE #else 2 #end) {
		FoxRenderer.allocationsThisFrame += 1;
		context = FoxRenderer.getContext();
		this.wrapMode = wrapMode;
		this.filter = filter;
		this.mipFilter = mipFilter;
	}

	public function asBitmapData():BitmapData {
		return BitmapData.fromTexture(glTexture);
	}

	// Copies this texture object, does not create new data on GPU
	public function copy():FoxTexture {
		var tex = new FoxTexture();
		tex.wrapMode = wrapMode;
		tex.filter = filter;
		tex.mipFilter = mipFilter;
		tex.glTexture = tex.glTexture;
		return tex;
	}

	public function generateMipmaps() {
		FoxRenderer.generateMipmap(context, this);
	}

	/**
		Resizes this texture. Intended for framebuffer textures,

		__Note:__ This will not work with textures that have been wrapped/loaded from a file.
	**/
	public function resize(width:Int, height:Int):FoxTexture {
		if(__format == null || __type == null) {
			FoxLog.warning("FoxTexture", "Wrapped/Loaded textures cannot be resized!!!");
			return this;
		}
		glTexture?.dispose();
		glTexture = FoxRenderer.createTextureStorage(width, height, __format, __type);
		return this;
	}

	/**
		Instance version of `FoxTexture.wrap()`

		Takes a `BitmapData` and sets it as the GPU texture

		__Note:__ This will not update any extra information of this texture, such as format or type.
	**/
	public function take(bitmap:BitmapData) {
		if(bitmap.__texture == null) bitmap.getTexture(context);
		glTexture = bitmap.__texture;
	}

	/**
		Instance version of `FoxTexture.wrapGL()`

		Takes a `Texture` and sets it as the GPU texture

		__Note:__ This will not update any extra information of this texture, such as format or type.
	**/
	public function takeGL(texture:TextureBase) {
		glTexture = texture;
	}

	public function destroy() {
		glTexture?.dispose();
		if(assetsKey != null) FoxCache.textures().remove(assetsKey);
		glTexture = null;
	}

	public static function fromBitmapData(data:BitmapData, format:Context3DTextureFormat=#if !foxlite_polymod Context3DTextureFormat.BGRA #else 1 #end, mipmaps:Bool=false, ?params:FoxTextureParams):FoxTexture {
		if(data == null) return null;
		// TODO: Add compressed textures
		var tex = FoxRenderer.getContext().createTexture(data.width, data.height, format, false);
		tex.uploadFromBitmapData(data, 0, mipmaps);

		var foxTex = FoxTexture.wrapGL(tex);
		if(params != null) {
			foxTex.wrapMode = params.wrapMode ?? FoxWrapMode.CLAMP;
			foxTex.filter = params.filter ?? FoxTextureFilter.LINEAR;
			foxTex.mipFilter = params.mipFilter ?? FoxMipFilter.MIPNONE;
		}
		return foxTex;
	}

	/**
		Loads a `FoxTexture` from an image located in `images/` (with .png extension)
	**/
	public static function fromImage(name:String, mipmaps:Bool=false, format:Context3DTextureFormat=#if !foxlite_polymod Context3DTextureFormat.BGRA #else 1 #end, ?params:FoxTextureParams):FoxTexture {
		return fromImageRaw(FoxLoaderUtil.imagePath(name), mipmaps, format, params);
	}
	
	/**
		Loads a `FoxTexture` using a full raw asset path (including extension)

		This may also include compressed textures with the .dds and .astc extension
	**/
	public static function fromImageRaw(name:String, mipmaps:Bool=false, format:Context3DTextureFormat=#if !foxlite_polymod Context3DTextureFormat.BGRA #else 1 #end, ?params:FoxTextureParams):FoxTexture {
		if(FoxCache.textures().exists(name)) return FoxCache.textures().get(name);
		
		var isDataUrl = StringTools.startsWith(name, "data:");
		if(!Assets.exists(name) && !isDataUrl) {
			FoxLog.warning('FoxTexture', 'Could not load image: ${name} (Not found.)');
			return null;
		}

		var foxTex = new FoxTexture();

		if(params != null) {
			foxTex.wrapMode = params.wrapMode ?? FoxWrapMode.CLAMP;
			foxTex.filter = params.filter ?? FoxTextureFilter.LINEAR;
			foxTex.mipFilter = params.mipFilter ?? FoxMipFilter.MIPNONE;
		}
		
		foxTex.assetsKey = name;
		FoxCache.textures().set(name, foxTex);

		function onImageLoaded(image:Image) {
			if(image == null) {
				FoxLog.warning('FoxTexture', 'Could not create image: ${name} (Image error.)');
				FoxCache.textures().remove(name);
				return;
			}
			else if(image?.buffer == null) {
				FoxLog.warning('FoxTexture', 'Could not create texture: ${name} (Asset was found, but Buffer is non-existant.)');
				FoxCache.textures().remove(name);
				return;
			}
			#if foxlite_verbose
			// We added it earlier but let the user know that it did load correctly
			FoxLog.log("FoxTexture", "Add texture to cache: " + (StringTools.startsWith(name, "data:") ? "<Base64URL_String>" : name));
			#end
			
			// Make it compatible with openfl...
			#if sys
			image.format = cast 2; // BGRA32
			image.premultiplied = true;
			#end

			function task() {
				var tex = FoxRenderer.getContext().createTexture(image.width, image.height, format, false);
				tex.__uploadFromImage(image);
				image = null;
				foxTex.takeGL(tex);
			}

			if(FoxRenderer.forceSyncLoading)
				task();
			else
				FoxRenderer.runTaskAtNextDraw(task);
		}

		function onImageError(e:Dynamic) {
			FoxLog.warning('FoxTexture', 'Could not create image: ${name} ($e)');
			FoxCache.textures().remove(name);
		}

		if(isDataUrl) {
			// We can load it right away
			var components = name.split(',');
			var image = Image.fromBase64(components[1], components[0].substr(5, components[0].indexOf(';base64')-5));
			onImageLoaded(image); 
		} 
		else if(["dds", "astc"].contains(Path.extension(name).toLowerCase())) {
			// Loading a compressed texture?
			foxTex = FoxTexture.fromImageCompressed(name, params);	
		}
		else {
			// If we're on the main thread, load it async, else lime's own thread pool system clashes with itself (bruh)
			if(ThreadPool.isMainThread() && !FoxRenderer.forceSyncLoading) {
				var future = Assets.loadImage(name, false);
				future.onComplete(onImageLoaded);
				future.onError(onImageError);
			}
			else
				onImageLoaded(Assets.getImage(name));
		}

		return foxTex;
	}

	/**
		Loads a compressed texture.

		__Note:__ This behaves exactly like `fromImageRaw`, meaning the path is relative and must include file extension

		Foxlite supports S3TC formats (DXT) in most platforms except mobile,
		and ASTC in most platforms, except some web browsers. __ASTC is only available in OpenGL 3+.__

		This expects a texture in the [DDS format](https://en.wikipedia.org/wiki/DirectDraw_Surface) or [ASTC format](https://en.wikipedia.org/wiki/Adaptive_scalable_texture_compression).
		A binary file containing a header, width, height, pixel format and data.
		This may also contain mipmaps. 3D Textures and texture arrays are not supported.

		You can use [AMD's Compressonator](https://gpuopen.com/compressonator/) to compress them in S3TC format. For ASTC, use [astc-encoder](https://github.com/ARM-software/astc-encoder).

		__Note 2:__ In WebGL, texture dimensions ***MUST*** be a multiple of 4
	**/
	public static function fromImageCompressed(name:String, ?params:FoxTextureParams):FoxTexture {
		if(!FoxRenderer.compressedTexturesSupported) {
			FoxLog.warning('FoxTexture', 'Error loading compressed texture: $name (Compressed textures are not supported on this device!)');
			return null;
		}

		if(FoxCache.textures().exists(name)) return FoxCache.textures().get(name);

		var isDataUrl = StringTools.startsWith(name, "data:");
		if(!Assets.exists(name) && !isDataUrl) {
			FoxLog.warning('FoxTexture', 'Could not load compressed image: ${name} (Not found.)');
			return null;
		}

		var foxTex = new FoxTexture();

		if(params != null) {
			foxTex.wrapMode = params.wrapMode ?? FoxWrapMode.CLAMP;
			foxTex.filter = params.filter ?? FoxTextureFilter.LINEAR;
			foxTex.mipFilter = params.mipFilter ?? FoxMipFilter.MIPNONE;
		}
		
		foxTex.assetsKey = name;
		#if foxlite_verbose
		FoxLog.log("FoxTexture", "Add texture to cache: " + (StringTools.startsWith(name, "data:") ? "<Base64URL_String>" : name));
		#end
		FoxCache.textures().set(name, foxTex);

		function onBytesLoaded(bytes:haxe.io.Bytes) {
			if(bytes == null) {
				FoxLog.warning('FoxTexture', 'Could not create compressed image: ${name} (ImageBytes error.)');
				FoxCache.textures().remove(name);
				return;
			}

			var magic = bytes.getInt32(0);
			var result = switch(magic) {
				case 0x20534444: __fromDDSBytes(bytes, foxTex); // DDS
				case 0x5CA1AB13: __fromASTCBytes(bytes, foxTex); // ASTC (astcenc)
				default: {
					FoxLog.warning('FoxTexture', 'Could not create compressed image: ${name} (Unrecognized compressed texture. Header: ${bytes.getString(0, 4)})');
					false;
				}
			}
			if(!result) FoxCache.textures().remove(name);
			// We added it earlier but let the user know that it did load correctly (also only do it if we actually created it)
			#if foxlite_verbose
			else FoxLog.log("FoxTexture", "Add compressed texture to cache: " + (StringTools.startsWith(name, "data:") ? "<Base64URL_String>" : name));
			#end
		}

		function onBytesError(e:Dynamic) {
			FoxLog.warning('FoxTexture', 'Could not create compressed image: ${name} ($e)');
			FoxCache.textures().remove(name);
		}

		if(isDataUrl) {
			// We can load it right away
			var components = name.split(',');
			
			var bytes = Base64.decode(components[1]);
			onBytesLoaded(bytes); 
		}
		else {
			// If we're on the main thread, load it async, else lime's own thread pool system clashes with itself (bruh)
			if(ThreadPool.isMainThread() && !FoxRenderer.forceSyncLoading) {
				var future = Assets.loadBytes(name);
				future.onComplete(onBytesLoaded);
				future.onError(onBytesError);
			}
			else
				onBytesLoaded(Assets.getBytes(name));
		}

		return foxTex;
	}

	/**
		Reference: https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide
		ETC1 and ETC2 compressonator formats were tasted trial and error
	**/
	@:dox(hide) @:noCompletion public static function __fromDDSBytes(bytes:Bytes, outTex:FoxTexture) {
		if(bytes.getInt32(0) != 0x20534444) {
			FoxLog.warning('FoxTexture', 'Invalid DDS image: ${outTex.assetsKey} (Bad magic number.)');
			return false;
		}
		var reader = new BytesInput(bytes);
		reader.position = 12;

		//var size   = reader.readInt32(); // pos=4
		//var flags  = reader.readInt32(); // pos=8
		var height = reader.readInt32(); // pos=12
		var width  = reader.readInt32(); // pos=16
		var pitch  = reader.readInt32(); // pos=20
		var depth  = reader.readInt32(); // pos=24, bpp
		var mips   = reader.readInt32(); // pos=28
		if(mips < 1) mips = 1;

		reader.position = 80; // pixel format flags start

		var pfFlags   = reader.readInt32(); //pos=80
		var pfFourCC  = reader.readString(4); //pos=84
			
		if((pfFlags & 0x4) == 0) { // check FourCC, if we don't have this it means DDS is uncompressed
			FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} (DDS is uncompressed and not supported.)');
			return false;
		}

		// Check fourCC, translate it to OpenGL s3tc format

		final s3tc = FoxRenderer.extensions.s3tc;
		final s3tc_srgb = FoxRenderer.extensions.s3tc_srgb;
		final rgtc = FoxRenderer.extensions.rgtc;
		final bptc = FoxRenderer.extensions.bptc;
		final etc1 = FoxRenderer.extensions.etc1;
		final etc2 = FoxRenderer.extensions.etc2;

		var err:String = "";
		if(StringTools.startsWith(pfFourCC, "DXT") && s3tc == null) {
			err = "EXT_texture_compression_s3tc";
		}
		else if((StringTools.startsWith(pfFourCC, "BC") || StringTools.startsWith(pfFourCC, "ATI")) && rgtc == null) {
			err = "EXT_texture_compression_rgtc";
		}
		else if(pfFourCC == "ETC1" && etc1 == null) {
			err = "OES_compressed_ETC1_RGB8_texture";
		}
		else if(StringTools.startsWith(pfFourCC, "ETC") && etc2 == null) {
			err = "ETC2 compressed texture format";
		}

		if(err != "") {
			FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} ($err not supported.)');
			return false;
		}

		var glFormat:Int = switch(pfFourCC) {
			case 'DXT1': s3tc.COMPRESSED_RGBA_S3TC_DXT1_EXT;
			case 'DXT3': s3tc.COMPRESSED_RGBA_S3TC_DXT3_EXT;
			case 'DXT5': s3tc.COMPRESSED_RGBA_S3TC_DXT5_EXT;
			case 'ATI1': rgtc.COMPRESSED_RED_RGTC1_EXT; // BC4
			case 'BC4S': rgtc.COMPRESSED_SIGNED_RED_RGTC1_EXT;
			case 'ATI2': rgtc.COMPRESSED_RED_GREEN_RGTC2_EXT; // BC5
			case 'BC5S': rgtc.COMPRESSED_SIGNED_RED_GREEN_RGTC2_EXT;
			case 'ETC1': etc1?.COMPRESSED_RGB_ETC1_WEBGL ?? etc1?.ETC1_RGB8_OES ?? 0;
			case 'ETC2': etc2.COMPRESSED_RGB8_ETC2;
			case 'ETCA': etc2.COMPRESSED_RGBA8_ETC2_EAC; // ETC2_RGBA
			case 'DX10': 0; // BC6+, BPTC, DXGI
			default: {
				FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} (unsupported DDS FourCC: $pfFourCC)');
				return false;
			}
		}

		var blockBytes:Int = switch(pfFourCC) {
			case 'DXT1', 'ATI1', 'BC4S', 'ETC1', 'ETC2': 8;
			case 'DXT3', 'DXT5', 'ATI2', 'BC5S', 'ETCA': 16;
			default: 0;
		}

		// Check dxgi and update
		var dxgiFormat:Int = 0;

		reader.position = 4 + 124; // magic + dds header
		if(pfFourCC == "DX10") {
			dxgiFormat = reader.readInt32(); // pos=128
			reader.position += 16; // skip dxgi header (pos=148)
		}

		if(dxgiFormat != 0) {
			try {
				glFormat = switch(dxgiFormat) {
					case DXGIFormat.BC1_UNORM: s3tc.COMPRESSED_RGBA_S3TC_DXT1_EXT;
					case DXGIFormat.BC1_UNORM_SRGB: s3tc_srgb.COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT;
					case DXGIFormat.BC2_UNORM: s3tc.COMPRESSED_RGBA_S3TC_DXT3_EXT;
					case DXGIFormat.BC2_UNORM_SRGB: s3tc_srgb.COMPRESSED_SRGB_ALPHA_S3TC_DXT3_EXT;
					case DXGIFormat.BC3_UNORM: s3tc.COMPRESSED_RGBA_S3TC_DXT5_EXT;
					case DXGIFormat.BC3_UNORM_SRGB: s3tc_srgb.COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT;
					case DXGIFormat.BC4_UNORM: rgtc.COMPRESSED_RED_RGTC1_EXT;
					case DXGIFormat.BC4_SNORM: rgtc.COMPRESSED_SIGNED_RED_RGTC1_EXT;
					case DXGIFormat.BC5_UNORM: rgtc.COMPRESSED_RED_GREEN_RGTC2_EXT;
					case DXGIFormat.BC5_SNORM: rgtc.COMPRESSED_SIGNED_RED_GREEN_RGTC2_EXT;
					case DXGIFormat.BC6H_UF16: bptc.COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT_EXT; 
					case DXGIFormat.BC6H_SF16: bptc.COMPRESSED_RGB_BPTC_SIGNED_FLOAT_EXT;
					case DXGIFormat.BC7_UNORM: bptc.COMPRESSED_RGBA_BPTC_UNORM_EXT;
					case DXGIFormat.BC7_UNORM_SRGB: bptc.COMPRESSED_SRGB_ALPHA_BPTC_UNORM_EXT;
					default: 0;
				}
			} catch(e:Dynamic) {
				FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} (S3TC_SRGB/RGTC/BPTC not supported in this device. Tried to load dxgi format: $dxgiFormat)');
				return false;
			}

			blockBytes = switch(dxgiFormat) {
				case DXGIFormat.BC1_UNORM, DXGIFormat.BC1_UNORM_SRGB, 
					 DXGIFormat.BC4_UNORM, DXGIFormat.BC4_SNORM: 8;
				default: 16;
			}

			if(glFormat == 0) {
				FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} (DXGI format not supported: $dxgiFormat)');
				return false;
			}
		}

		// Calculate mip levels and slices
		var texData:Array<DDSMipData> = [];
		texData.resize(mips);

		var offset = reader.position;
		var mipWidth = width;
		var mipHeight = height;

		for(level in 0...mips) {
			var blocksW = Std.int(Math.max(1, Math.floor((mipWidth + 3) / 4)));
			var blocksH = Std.int(Math.max(1, Math.floor((mipHeight + 3) / 4)));
			var chunkSize = blocksW * blocksH * blockBytes;

			var data:ArrayBufferView = new UInt8Array(#if js chunkSize #else null, bytes #end);
					
			#if js
			Bytes.ofData(data.buffer).blit(0, bytes, offset, chunkSize);
			#else
			// Native doesn't need blitting, we can just use the buffer pointer
			data.byteLength = chunkSize;
			data.length = blocksW * blocksH;
			data.byteOffset = offset;
			#end

			texData[level] = {width: mipWidth, height: mipHeight, buffer: data};

			offset += chunkSize;
			mipWidth = Std.int(Math.max(1, mipWidth >> 1));
			mipHeight = Std.int(Math.max(1, mipHeight >> 1));
		}

		// Create texture along with mipmaps (if provided)
		function task() {
			var context = FoxRenderer.getContext();
			var gl = context.gl;
			var tex = FoxRenderer.createOpenFLTemplateTexture(width, height, true);

			tex.__internalFormat = glFormat;
			tex.__format = gl.RGBA; // just in case
			
			for(level=>data in texData) {
				gl.compressedTexImage2D(gl.TEXTURE_2D, level, glFormat, data.width, data.height, 0, data.buffer);

				var error = gl.getError();
				if(error != 0) {
					FoxLog.warning('FoxTexture', 'Warning: Error when loading compressed image: ${outTex.assetsKey}. ${level == 0 ? "Texture" : "Mipmaps"} might not be visible (code: $error)');
				}
			}
			
			context.__bindGLTexture2D(null);

			bytes = null;
			outTex.takeGL(tex);
		}

		if(FoxRenderer.forceSyncLoading)
			task();
		else
			FoxRenderer.runTaskAtNextDraw(task);
		return true;
	}

	/**
		Reference: https://github.com/ARM-software/astc-encoder/blob/main/Docs/FileFormat.md
		Does not support loading mipmaps for now
	**/
	@:dox(hide) @:noCompletion public static function __fromASTCBytes(bytes:Bytes, outTex:FoxTexture) {
		if(bytes.getInt32(0) != 0x5CA1AB13) {
			FoxLog.warning('FoxTexture', 'Invalid DDS image: ${outTex.assetsKey} (Bad magic number.)');
			return false;
		}

		final astc = FoxRenderer.extensions.astc;
		
		if(astc == null) {
			FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} (KHR_texture_compression_astc_ldr not supported.)');
			return false;
		}

		var reader = new BytesInput(bytes);
		reader.position = 4;

		var blockX = reader.readByte();
		var blockY = reader.readByte();
		var blockZ = reader.readByte();

		var dimX = reader.readUInt24();
		var dimY = reader.readUInt24();
		var dimZ = reader.readUInt24();

		var blockSize = StringTools.hex(blockY + (blockX << 4)).toUpperCase(); // XY
		var glFormat:Int = switch(blockSize) {
			case '44': astc.COMPRESSED_RGBA_ASTC_4x4_KHR;
			case '54': astc.COMPRESSED_RGBA_ASTC_5x4_KHR;
			case '55': astc.COMPRESSED_RGBA_ASTC_5x5_KHR;
			case '65': astc.COMPRESSED_RGBA_ASTC_6x5_KHR;
			case '66': astc.COMPRESSED_RGBA_ASTC_6x6_KHR;
			case '85': astc.COMPRESSED_RGBA_ASTC_8x5_KHR;
			case '86': astc.COMPRESSED_RGBA_ASTC_8x6_KHR;
			case '88': astc.COMPRESSED_RGBA_ASTC_8x8_KHR;
			case 'A5': astc.COMPRESSED_RGBA_ASTC_10x5_KHR;
			case 'A6': astc.COMPRESSED_RGBA_ASTC_10x6_KHR;
			case 'A8': astc.COMPRESSED_RGBA_ASTC_10x8_KHR;
			case 'AA': astc.COMPRESSED_RGBA_ASTC_10x10_KHR;
			case 'CA': astc.COMPRESSED_RGBA_ASTC_12x10_KHR;
			case 'CC': astc.COMPRESSED_RGBA_ASTC_12x12_KHR;
			default: {
				FoxLog.warning('FoxTexture', 'Could not create compressed image: ${outTex.assetsKey} (unsupported ASTC format: ${blockX}x${blockY})');
				return false;
			}
		}

		var byteLength = reader.length - reader.position;
		var data:ArrayBufferView = new UInt8Array(#if js byteLength #else null, bytes #end);
					
		#if js
		Bytes.ofData(data.buffer).blit(0, bytes, reader.position, byteLength);
		#else
		// Native doesn't need blitting, we can just use the buffer pointer
		data.byteLength = byteLength;
		data.length = byteLength;
		data.byteOffset = reader.position;
		#end

		// Create texture
		function task() {
			var context = FoxRenderer.getContext();
			var gl = context.gl;
			var tex = FoxRenderer.createOpenFLTemplateTexture(dimX, dimY, true);

			tex.__internalFormat = glFormat;
			tex.__format = gl.RGBA; // just in case

			gl.compressedTexImage2D(gl.TEXTURE_2D, 0, glFormat, dimX, dimY, 0, data);
			
			var error = gl.getError();
			if(error != 0) {
				FoxLog.warning('FoxTexture', 'Error when loading compressed image: ${outTex.assetsKey}. Texture might not be visible (code: $error)');
			}

			context.__bindGLTexture2D(null);

			bytes = null;
			outTex.takeGL(tex);
		}

		if(FoxRenderer.forceSyncLoading)
			task();
		else
			FoxRenderer.runTaskAtNextDraw(task);

		return true;
	}

	/**
		Creates a texture on the GPU, this texture can be used as a render target.

		For a friendly list of available formats, check MDN's [texImage2D() types](https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/texImage2D#type). 
		
		It applies for standard OpenGL aswell, with the exception of `WEBGL_`.
	**/
	public static function create(width:Int, height:Int, format:String="rgba", type:String="unsigned_byte"):FoxTexture {
		var tex = FoxTexture.wrapGL(FoxRenderer.createTextureStorage(width, height, format, type));
		tex.__format = format.toUpperCase();
		tex.__type = type.toUpperCase();
		return tex;
	}

	/**
		Lighter version of fromBitmapData()
	
		Note: Use this **if** the bitmap data **already has a GPU texture attached** to it.
	*/
	public static function wrap(bitmap:BitmapData):FoxTexture {
		var texture = new FoxTexture();
		texture.take(bitmap);
		return texture;
	}

	/*
	* For wrapping GLTextures 
	*/
	public static function wrapGL(glTexture:TextureBase):FoxTexture {
		var texture = new FoxTexture();
		texture.glTexture = glTexture;
		return texture;
	}

}