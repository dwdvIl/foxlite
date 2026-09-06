package foxlite.texture;

import Reflect;
import foxlite.renderer.FoxRenderer;
import foxlite.texture.FoxTexture;
import haxe.io.Bytes;
import lime.math.Vector2;
import lime.utils.Float32Array;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;
#if foxlite_polymod
import lime.graphics.opengl.GL;
#end

/*class FoxTextureBufferFormat {
	public inline static final INT8 = 0;
	public inline static final UINT8 = 1;
	public inline static final INT16 = 2;
	public inline static final INT32 = 3;
	public inline static final FLOAT32 = 4;
}*/

/**
	A `FoxTexture` that can be used to store and sample data from the CPU to the GPU.

	**It is intended to be used as a dynamic array, so the width of the texture changes, but the height is always 1.**

	*It only supports 32-bit Float values for now.*
	
	Its usage in a `FoxFramebuffer` is currently unknown.

	Limitations: 16384 elements maximum, however some devices could have an even lower limit.
**/
class FoxTextureBuffer extends FoxTexture {

	public var buffer:Float32Array;

	/**
		The pixel size for this texture, useful when sampling the buffer in the shader when `texelFetch` is not supported, 
		just pass it as an uniform and multiply the indices by this value.

		As of now, `pixelSize.y` is always 0.
	**/
	public var pixelSize:Vector2 = new Vector2();

	var _length:Int = 0;

	var _glFormat:Int = -1;
	var _glType:Int = -1;

	/**
		Creates a new texture buffer to store data. To upload it to the GPU, call `updateGPU()` afterwards.

		@param length Specifies the number of elements (pixels)
		@param channels The number of channels to use in the texture, they correspond to Red, Green, Blue and Alpha
	**/
	public function new(length:Int, channels:Int=1) {
		super();
		create(length, channels);
		filter = FoxTextureFilter.NEAREST;
		wrapMode = FoxWrapMode.CLAMP;
	}

	/**
		Re-allocates the buffer both on the CPU, useful when changing the length of the array is needed.

		To upload it to the GPU, call `updateGPU()` afterwards.

		__Note:__ The contents of the previous buffer are lost in favor of the new one, you might want to write your data back.

		@param length The width of the texture.
		@param channels The number of channels to use in the texture, they correspond to Red, Green, Blue and Alpha.
	**/
	public function create(length:Int, channels:Int) {
		var gl = context.gl;
		destroy(); // Free memory

		_length = length;
		
		buffer = new Float32Array(length * channels);
		bytes = cast buffer.buffer;
		FoxRenderer.allocationsThisFrame += 2;

		var formatString = switch(channels) {
			case 1: "R";
			case 2: "RG";
			case 3: "RGB";
			case 4: "RGBA";
			default: "";
		}
		
		formatString += "32F";

		/*if(!(format == FoxTextureBufferFormat.UINT8 && channels == 4)) formatString += switch(format) {
			case FoxTextureBufferFormat.UINT8: "8";
			case FoxTextureBufferFormat.INT8: "8I";
			case FoxTextureBufferFormat.INT16: "16I";
			case FoxTextureBufferFormat.INT32: "32I";
			case FoxTextureBufferFormat.FLOAT32: "32F";
			default: "";
		}*/

		/*var typeString = switch(format) {
			case FoxTextureBufferFormat.UINT8: "unsigned_byte";
			case FoxTextureBufferFormat.INT8: "byte";
			case FoxTextureBufferFormat.INT16: "short";
			case FoxTextureBufferFormat.INT32: "int";
			case FoxTextureBufferFormat.FLOAT32: "float";
			default: "";
		}*/

		final typeString = "FLOAT";

		if(formatString == "32F" || formatString == "") {
			trace("[Foxlite > FoxTextureBuffer]: Invalid buffer format!");
			return;
		}

		var texFmtData = FoxRenderer.getTextureFormat(formatString);
		_glFormat = texFmtData.format;
		_glType = Reflect.field(gl, typeString.toUpperCase());

		glTexture = FoxRenderer.createTextureStorage(length, 1, formatString, typeString);
		pixelSize.x = 1.0 / length;
	}

	/**
		Uploads the texture buffer to the GPU.

		Call this when you're done writing data to the buffer.
	**/
	public inline function updateGPU() {
		var gl = #if foxlite_polymod GL; #else context.gl; #end // Use lime GL for HScript
		
		#if (js && html5)
		gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 0); // do NOT PREMULTIPLY RGB WITH ALPHA, it will MESS UP texture buffers.
		#end

		context.__bindGLTexture2D(glTexture.__textureID);
		gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, _length, 1, _glFormat, _glType, buffer);
	}

	// -------------------------------------------------------
	// Perhaps use an interface instead
	var bytes:Bytes;

	public inline function setFloat(pos:Int, v:Float):Void {
		#if !foxlite_polymod
		buffer[pos] = v;
		#else
		bytes.setFloat(pos<<2, v);
		#end
	}

	public inline function getFloat(pos:Int):Float {
		#if !foxlite_polymod
		return buffer[pos];
		#else
		return bytes.getFloat(pos<<2);
		#end
	}
	// -------------------------------------------------------

	public inline function setVector2(pos:Int, v:Vector2) {
		setFloat(pos  , v.x);
		setFloat(pos+1, v.y);
	}

	public inline function setVector3(pos:Int, v:Vector3D) {
		setFloat(pos  , v.x);
		setFloat(pos+1, v.y);
		setFloat(pos+2, v.z);
	}

	public inline function setVector4(pos:Int, v:Vector3D) {
		setFloat(pos  , v.x);
		setFloat(pos+1, v.y);
		setFloat(pos+2, v.z);
		setFloat(pos+3, v.w);
	}

	public inline function setMatrix4(pos:Int, v:Matrix3D) {
		var a = v.rawData.__array;
		for(i in 0...16) setFloat(pos+i, a[i]);
	}

	public inline function setArray(pos:Int, v:Array<Float>) {
		buffer.set(v, pos);
	}

	/**
		Returns the width of the buffer texture.

		To get the actual length, check `buffer`
	**/
	public inline function getLength():Int {
		return _length;
	}

	public override function destroy() {
		buffer = null;
		bytes = null;
		super.destroy();
	}
}