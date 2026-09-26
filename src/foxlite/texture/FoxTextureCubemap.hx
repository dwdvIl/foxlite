package foxlite.texture;

import foxlite.renderer.FoxRenderer;
import foxlite.texture.FoxCubemapSide;
import foxlite.texture.FoxTexture;
import openfl.display.BitmapData;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.CubeTexture;

class FoxTextureCubemap extends FoxTexture {

	public function setSideFromBitmapData(data:BitmapData, side:FoxCubemapSide, format:Context3DTextureFormat=#if !foxlite_polymod Context3DTextureFormat.BGRA #else 1 #end, mipmaps:Bool=false) {
		var tex:CubeTexture;
		if(glTexture == null) {
			glTexture = context.createCubeTexture(data.width, format, false, 0);
		}
		tex = cast glTexture;
		tex.uploadFromBitmapData(data, side, 0, mipmaps);
	}
	
	public static function wrapGL(glTexture:CubeTexture):FoxTextureCubemap {
		var texture = new FoxTextureCubemap();
		texture.glTexture = glTexture;
		return texture;
	}

	/*
	* Create on GPU
	*/
	public static function create(size:Int, format:String="rgba", type:String="unsigned_byte"):FoxTextureCubemap {
		var tex = FoxTextureCubemap.wrapGL(FoxRenderer.createTextureCubemapStorage(size, format, type));
		tex.__format = format.toUpperCase();
		tex.__type = type.toUpperCase();
		return tex;
	}

	public override function resize(width:Int, height:Int):FoxTextureCubemap {
		if(__format == null || __type == null) {
			FoxLog.warning("FoxTexture", "Wrapped/Loaded textures cannot be resized!!!");
			return this;
		}
		glTexture?.dispose();
		glTexture = FoxRenderer.createTextureCubemapStorage(width, __format, __type);
		return this;
	}

	public override function take(bitmap:BitmapData) {}
}