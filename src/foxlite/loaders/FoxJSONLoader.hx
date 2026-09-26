package foxlite.loaders;

import flixel.util.FlxColor;
import foxlite.environment.FoxEnvironment;
import Reflect;
import Array;
import haxe.Json;
import haxe.io.Path;
import haxe.ds.StringMap;
import foxlite.animation.FoxAnimation;
import foxlite.animation.FoxTrackType;
import foxlite.animation.FoxAnimationTrack;
import foxlite.animation.FoxEaseType;
import foxlite.animation.data.FoxTrackData;
import foxlite.skin.FoxSkinData;
import foxlite.skin.FoxBone;
import foxlite.stencil.FoxStencilAction;
import foxlite.stencil.FoxStencilActionType;
import foxlite.texture.FoxTexture;
import foxlite.texture.FoxTextureFilter;
import foxlite.texture.FoxMipFilter;
import foxlite.texture.FoxWrapMode;
import foxlite.polyfill.VectorFactory;
import foxlite.FoxCache;
import foxlite.FoxShader;
import foxlite.loaders.FoxLoaderUtil;
import foxlite.material.FoxMaterial;
import foxlite.material.FoxBlendMode;
import foxlite.material.FoxDepthCompareMode;
import foxlite.material.FoxTriangleFace;
import foxlite.mesh.FoxMesh;
import openfl.geom.Matrix3D;

class FoxJSONLoader {
	
	/**
		Loads a model and material from their foxlite `.json` file.
	**/
	public static function loadModel(name:String):{meshes:Array<FoxMesh>, materials:Map<String, FoxMaterial>} {
		// Check cache
		if(FoxCache.meshes().exists(name)) {
			var meshes = FoxCache.meshes().get(name);
			var materials:Map<String, FoxMaterial> = new StringMap();
			for(m in meshes) {
				if(!materials.exists(m.material.name)) materials.set(m.material.name, m.material);
			}
			return {meshes:meshes, materials: materials};
		}
		
		var modelData:Array<Dynamic> = FoxLoaderUtil.loadJSON(name);
		if((modelData?.length ?? 0) == 0) return null;

		var meshes:Array<FoxMesh> = [];
		var materials:Map<String, FoxMaterial> = new StringMap();

		var path:String = Path.directory(name) + '/';

		for(model in modelData) {
			var material:FoxMaterial = null;
			if(model.material != null) {
				#if foxlite_verbose
				FoxLog.log("FoxJSONLoader", "Loading material file: " + model.material.split(":")[0]);
				#end
				material = FoxMaterial.fromJSON(path + model.material); // Adds to cache automatically
				if(material == null) {
					FoxLog.warning("FoxMaterial", "material not found!! " + model.material);
				}
				else materials.set(material.name, material);
			}

			var mesh = new FoxMesh();
			mesh.setArrays(model.vertices, model.uvtData, model.indices, material, model.normals, model.colors, model.weights, model.influences);
			mesh.calculateBounds(model.vertices);
			mesh.assetsKey = name;
			meshes.push(mesh);
		}

		FoxCache.meshes().set(name, meshes);

		return {meshes:meshes, materials: materials};
	}

	/**
		Loads a collection of FoxMaterial from a foxlite `.json` file.
	**/
	public static function loadMaterialLibrary(name:String):Map<String, FoxMaterial> {
		if(FoxCache.materialLibs().exists(name)) {
			return FoxCache.materialLibs().get(name);
		}

		var data = FoxLoaderUtil.loadJSON(name);
		if(data == null) return null;

		var materials:Map<String, FoxMaterial> = new StringMap();
		materials.clear();

		for(matName in Reflect.fields(data)) {
			var mat:Dynamic = Reflect.field(data, matName);

			// Create material
			var material = new FoxMaterial();
			material.name = matName;
			material.assetsKey = name;
			if(Std.isOfType(mat.blendMode, String)) material.blendMode = FoxBlendMode.fromString(mat.blendMode);
			if(Std.isOfType(mat.alphaScissor, Bool)) material.alphaScissor = mat.alphaScissor;
			if(Std.isOfType(mat.depthWrite, Bool)) material.depthWrite = mat.depthWrite;
			if(Std.isOfType(mat.renderPriority, Int)) material.renderPriority = mat.renderPriority;
			if(mat.wireframe == true) material.renderMode = 0x0001; // GL.LINES
			if(Std.isOfType(mat.lineWidth, Int) || Std.isOfType(mat.lineWidth, Float)) material.lineWidth = mat.lineWidth;

			if(mat.params != null) {
				for(p in Reflect.fields(mat.params)) {
					material.params.set(p, Reflect.field(mat.params, p));
				}
			}
		
			// Load shader
			if(Std.isOfType(mat.shader, String)) {
				material.shader = FoxShader.fromAsset(mat.shader, mat.shaderFlags);
			}
			
			// Load textures
			if(mat.textures != null) {
				for(samplerName in Reflect.fields(mat.textures)) {
					var tex = Reflect.field(mat.textures, samplerName);
					if(tex == null) continue;
					var texture = __parseTexture(tex);
					if(texture != null) material.textures.set(samplerName, texture);
				}
			}
			
			if(Std.isOfType(mat.depthTest, Bool)) material.depthTest = mat.depthTest;

			if(Std.isOfType(mat.depthFunc, String)) material.depthFunc = FoxDepthCompareMode.fromString(mat.depthFunc);
			if(Std.isOfType(mat.culling, String)) material.culling = FoxTriangleFace.fromString(mat.culling);
			if(Std.isOfType(mat.shadowCulling, String)) material.shadowCulling = FoxTriangleFace.fromString(mat.shadowCulling);

			// Stencil
			if(mat.stencil != null) {
				var stencil = new FoxStencilAction();
				var sd:Dynamic = mat.stencil;
				if(Std.isOfType(sd.value, Int) || Std.isOfType(sd.value, Float)) stencil.value = Std.int(sd.value);
				if(Std.isOfType(sd.read, Bool)) stencil.read = sd.read;
				if(Std.isOfType(sd.write, Bool)) stencil.write = sd.write;
				if(Std.isOfType(sd.readMask, String)) stencil.readMask = Std.parseInt(sd.readMask);
				if(Std.isOfType(sd.writeMask, String)) stencil.writeMask = Std.parseInt(sd.writeMask);
				if(Std.isOfType(sd.triangleFace, String)) stencil.triangleFace = FoxTriangleFace.fromString(sd.triangleFace);
				if(Std.isOfType(sd.actionOnBothPass, String)) stencil.actionOnBothPass = FoxStencilActionType.fromString(sd.actionOnBothPass);
				if(Std.isOfType(sd.actionOnDepthFail, String)) stencil.actionOnDepthFail = FoxStencilActionType.fromString(sd.actionOnDepthFail);
				if(Std.isOfType(sd.actionOnFail, String)) stencil.actionOnFail = FoxStencilActionType.fromString(sd.actionOnFail);
				material.stencil = stencil;
			}

			// Environment
			if(mat.environment != null) {
				var env = new FoxEnvironment();
				if(Std.isOfType(mat.fogColor, String)) env.fogColor = FlxColor.fromString(mat.fogColor);
				if(Std.isOfType(mat.fogStart, Float) || Std.isOfType(mat.fogStart, Int)) env.fogStart = mat.fogStart;
				if(Std.isOfType(mat.fogEnd, Float) || Std.isOfType(mat.fogEnd, Int)) env.fogEnd = mat.fogEnd;
				if(Std.isOfType(mat.ambientLight, String)) env.ambientLight = FlxColor.fromString(mat.ambientLight);
				if(Std.isOfType(mat.skyOffset, Array)) env.skyOffset.setTo(mat.skyOffset[0], mat.skyOffset[1]);
				if(mat.skyTexture != null) {
					env.skyTexture = __parseTexture(mat.skyTexture);
				}
			}

			materials.set(matName, material);
		}

		FoxCache.materialLibs().set(name, materials);

		return materials;
	}

	@:dox(hide)
	@:noCompletion public static function __parseTexture(tex:Dynamic):FoxTexture {
		// TODO: add more formats maybe?
		var mipFilter = Std.isOfType(tex.mipFilter, String) ? FoxMipFilter.fromString(tex.mipFilter) : FoxMipFilter.MIPNONE;
		return FoxTexture.fromImage(FoxLoaderUtil.imagePath(tex.name), mipFilter != FoxMipFilter.MIPNONE, null, {
			wrapMode: Std.isOfType(tex.wrapMode, String) ? FoxWrapMode.fromString(tex.wrapMode) : FoxWrapMode.CLAMP,
			mipFilter: mipFilter,
			filter: Std.isOfType(tex.filter, String) ? FoxTextureFilter.fromString(tex.filter) : FoxTextureFilter.LINEAR
		});
	}

	/**
		Loads skin data from a `.json` file.

		The skin data contains the bone structure to animate models.

		__Note:__ This resource is not cached, use `FoxSkinData.copy()` instead.
	**/
	public static function loadSkinData(name:String):FoxSkinData {
		var data:Array<Dynamic> = Json.parse(FoxLoaderUtil.loadText(name));
		if(data == null) return null;
		
		var skin = new FoxSkinData();
		skin.assetsKey = name;

		for(bd in data) {
			var rest = new Matrix3D(VectorFactory.Float(bd.rest));
			var bone = new FoxBone(rest);
			bone.name = bd.name;
			
			if(bd.pose != null) {
				var pose = bd.pose;
				if(Std.isOfType(pose?.position, Array)) bone.position.setTo(bd.pose.position[0], bd.pose.position[1], bd.pose.position[2]);
				if(Std.isOfType(pose?.rotation, Array)) bone.rotation.setTo(bd.pose.rotation[0], bd.pose.rotation[1], bd.pose.rotation[2]);
				if(Std.isOfType(pose?.scale, Array)) bone.scale.setTo(bd.pose.scale[0], bd.pose.scale[1], bd.pose.scale[2]);
			}
			skin.addBone(bone, bd.parent);
		}

		return skin;
	}

	/**
		Loads an animation collection from a `.json` file
	**/
	public static function loadAnimationLibrary(name:String):Map<String, FoxAnimation> {
		if(FoxCache.animationLibs().exists(name)) {
			return FoxCache.animationLibs().get(name);
		}

		var animData:Dynamic = FoxLoaderUtil.loadJSON(name);
		if(animData == null) return null;

		var map:Map<String, FoxAnimation> = new StringMap();

		for(animName in Reflect.fields(animData)) {
			var data:Dynamic = Reflect.field(animData, animName);
			var anim = new FoxAnimation(animName);

			var useMaxFrameTimes:Bool = false;

			if(Std.isOfType(data.duration, Float) || Std.isOfType(data.duration, Int)) anim.duration = Math.max(data.duration, 0);
			else {
				FoxLog.warning('FoxJSONLoader', 'Animation "$animName" duration is invalid. Keyframe times will be used instead.');
				useMaxFrameTimes = true;
			}
			if(Std.isOfType(data.loop, Bool)) anim.loop = data.loop;

			for(trackName in Reflect.fields(data.tracks)) {
				var tData:Dynamic = Reflect.field(data.tracks, trackName);
				var tType:Int = Std.isOfType(tData.type, String) ? FoxTrackType.fromString(tData.type) : (Std.isOfType(tData.type, Int) || Std.isOfType(tData.type, Float) ? Std.int(tData.type) : -1);
				if(tType < 0) {
					FoxLog.warning('FoxJSONLoader', 'Track "$trackName" of animation "$animName" has an invalid type, skipping.');
					continue;
				}
				var track:FoxAnimationTrack<Any> = anim.addTrack(trackName, tType);
				if(Std.isOfType(tData.frames, Array)) {
					final stride = 3;
					var idx = 0;
					var arr:Array<Dynamic> = tData.frames;
					while(idx < arr.length) {
						var e:Dynamic = arr[idx+2];
						var easing:Int = Std.isOfType(e, String) ? FoxEaseType.fromString(e) : (Std.isOfType(e, Int) || Std.isOfType(e, Float) ? Std.int(e) : FoxEaseType.LINEAR);
						track.addFrame(arr[idx], FoxTrackData.getValueForType(tType, arr[idx+1]), easing);
						if(useMaxFrameTimes)
							anim.duration = Math.max(anim.duration, arr[idx]);
						
						idx += stride;
					}
				}
			}
			map.set(animName, anim);
		}

		FoxCache.animationLibs().set(name, map);

		return map;
	}
}