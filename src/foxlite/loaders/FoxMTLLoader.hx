package foxlite.loaders;

import StringTools;
import EReg;
import haxe.io.Path;
import haxe.ds.StringMap;
import foxlite.FoxShader;
import foxlite.loaders.FoxLoaderUtil;
import foxlite.material.FoxMaterial;
import foxlite.material.FoxTriangleFace;
import foxlite.texture.FoxTexture;
import foxlite.texture.FoxWrapMode;
import openfl.geom.Vector3D;
import openfl.Assets;

class FoxMTLLoader {
	
	@:dox(hide) public static final n = "(-?\\d+[e.]?\\d*)"; // Regex int/float token

	@:dox(hide) public static final tokenizer = {
		def:  new EReg('(newmtl|Ns|Ni|illum|d)\\s+(.+)', 'g'),
		K: 	  new EReg('(K[ased])\\s+$n\\s+$n\\s+$n', 'g'),
		map:  new EReg('(map_\\w+).+?(\\S+\\.[a-zA-Z]+)', 'g'),
		type: new EReg('(#|\\w+).*', 'g')
	};

	/**
		Loads a MTL file for an OBJ mesh, although it can be loaded independently if you need it.

		@param name The MTL asset path
		@param extraShaderFlags (Optional) A String array containing additional flags you want to use for this material
		@param customShaderPath (Optional) The path to a custom shader if you need it. The default is Foxlite's basic_lighting
		
		@returns A Map containing the materials inside the MTL by their name.
	**/
	public static function load(name:String, ?extraShaderFlags:Array<String>, ?customShaderPath:String):Map<String, FoxMaterial> {
		if(FoxCache.materialLibs().exists(name)) return FoxCache.materialLibs().get(name);
		var mtl = FoxLoaderUtil.loadText(name);
		if(mtl == null) {
			FoxLog.warning('FoxOBJLoader', 'Could not load MTL: ${name} (Not found.)');
			return null;
		}
		var dir = Path.directory(name) + '/';

		if(extraShaderFlags == null) extraShaderFlags = [];

		var curMat:FoxMaterial = null;
		var matShaderFlags:Array<String> = ["SOLID"].concat(extraShaderFlags); // "SOLID" Will be removed if map_Kd is present

		var materials:Map<String, FoxMaterial> = new StringMap();

		FoxLoaderUtil.forEachLine(mtl, line -> {
			if(!tokenizer.type.match(line)) return;

			switch(tokenizer.type.matched(1)) {
				case 'newmtl': {
					var tk = tokenizer.def;
					tk.match(line);

					// Finish previous work
					if(curMat != null) curMat.shader = FoxShader.fromAsset(customShaderPath ?? FoxShader.BASIC, matShaderFlags);
					
					curMat = new FoxMaterial();
					curMat.culling = FoxTriangleFace.BACK;
					curMat.name = StringTools.trim(tk.matched(2));
					curMat.assetsKey = name;
					materials.set(curMat.name, curMat);
					matShaderFlags = ["SOLID"].concat(extraShaderFlags);
				};
				// Basic params
				case 'd': {
					var tk = tokenizer.def;
					tk.match(line);

					var p:Array<Float> = curMat.params.get("color");
					if(p == null) {
						p = [1, 1, 1, 1];
						curMat.params.set("color", p);
					}
					p[3] = Std.parseFloat(tk.matched(2));
				};
				case 'Ka': {
					var tk = tokenizer.K;
					tk.match(line);

					var p:Array<Float> = curMat.params.get("color");
					if(p == null) {
						p = [1, 1, 1, 1];
						curMat.params.set("color", p);
					}
					p[0] = Std.parseFloat(tk.matched(2));
					p[1] = Std.parseFloat(tk.matched(3));
					p[2] = Std.parseFloat(tk.matched(4));
				};
				case 'Ke': {
					var tk = tokenizer.K;
					tk.match(line);

					curMat.params.set("uEmissive", [
						Std.parseFloat(tk.matched(2)),
						Std.parseFloat(tk.matched(3)),
						Std.parseFloat(tk.matched(4))
					]);
				};
				case 'Ks': {
					var tk = tokenizer.K;
					tk.match(line);

					curMat.params.set("uSpecular", [
						Std.parseFloat(tk.matched(2)),
						Std.parseFloat(tk.matched(3)),
						Std.parseFloat(tk.matched(4))
					]);
				};
				case 'Kd': {
					var tk = tokenizer.K;
					tk.match(line);

					var p:Array<Float> = curMat.params.get("color");
					if(p == null) {
						p = [
							Std.parseFloat(tk.matched(2)), 
							Std.parseFloat(tk.matched(3)), 
							Std.parseFloat(tk.matched(4)), 1];
						curMat.params.set("color", p);
					}
					else {
						p[0] = Std.parseFloat(tk.matched(2));
						p[1] = Std.parseFloat(tk.matched(3));
						p[2] = Std.parseFloat(tk.matched(4));
					}
				};
				// Textures
				case 'map_Kd': {
					var tk = tokenizer.map;
					tk.match(line);
					curMat.textures.set("bitmap", _loadTexture(dir + tk.matched(2)));
					matShaderFlags.remove("SOLID");
				};
				case 'map_Ke': {
					var tk = tokenizer.map;
					tk.match(line);
					curMat.textures.set("emissiveMap", _loadTexture(dir + tk.matched(2)));
					matShaderFlags.push("EMISSIVE_MAP");
					
					// Make sure emissives are visible
					curMat.params.set("uEmissive", [1, 1, 1]);
				};
				case 'map_Bump': {
					var tk = tokenizer.map;
					tk.match(line);
					curMat.textures.set("normalMap", _loadTexture(dir + tk.matched(2)));
					matShaderFlags.push("NORMAL_MAP");
				};
				case 'map_ORM': {
					var tk = tokenizer.map;
					tk.match(line);
					curMat.textures.set("ormMap", _loadTexture(dir + tk.matched(2)));
					matShaderFlags.push("ORM_MAP");
				};
			}
		});

		// Finish previous work
		if(curMat != null) curMat.shader = FoxShader.fromAsset(customShaderPath ?? FoxShader.BASIC, matShaderFlags);

		// Add to cache
		FoxCache.materialLibs().set(name, materials);

		return materials;
	}

	@:dox(hide)
	@:noCompletion public static function _loadTexture(name:String):FoxTexture {
		// Check if image exists relative to our model
		var relPath = FoxLoaderUtil.filePath(name);
		var tex:FoxTexture = null;
		#if cne
		if(Assets.exists(relPath)) tex = FoxTexture.fromImageRaw(relPath);
		// Nothing, load from `images/`
		else tex = FoxTexture.fromImage(Path.withoutExtension(name));
		#else
		tex = FoxTexture.fromImageRaw(relPath);
		#end
		if(tex != null) {
			tex.wrapMode = FoxWrapMode.REPEAT;
		}
		return tex;
	}

}