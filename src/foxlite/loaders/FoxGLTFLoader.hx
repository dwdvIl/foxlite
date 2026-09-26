package foxlite.loaders;

import StringTools;
import haxe.Json;
import haxe.io.Path;
import haxe.io.Bytes;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.crypto.Base64;
import foxlite.FoxShader;
import foxlite.animation.FoxAnimation;
import foxlite.animation.FoxTrackType;
import foxlite.animation.FoxAnimationTrack;
import foxlite.animation.FoxEaseType;
import foxlite.animation.FoxAnimationPlayer;
import foxlite.culling.BoundingBox;
import foxlite.group.FoxObjectGroup;
import foxlite.material.FoxMaterial;
import foxlite.material.FoxTriangleFace;
import foxlite.material.FoxBlendMode;
import foxlite.math.FoxMathUtil;
import foxlite.mesh.FoxMesh;
import foxlite.mesh.buffer.FoxVertexBufferType;
import foxlite.mesh.buffer.FoxVertexBuffer;
import foxlite.mesh.buffer.FoxIndexBuffer;
import foxlite.polyfill.VectorFactory;
import foxlite.renderer.FoxRenderer;
import foxlite.skin.FoxSkinData;
import foxlite.skin.FoxBone;
import foxlite.skin.FoxArmature;
import foxlite.lights.FoxSpotLight;
import foxlite.lights.FoxDirectionalLight;
import foxlite.lights.FoxPointLight;
import foxlite.lights.FoxBaseLight;
import foxlite.FoxObject;
import foxlite.texture.FoxMipFilter;
import foxlite.texture.FoxTextureFilter;
import foxlite.texture.FoxWrapMode;
import foxlite.texture.FoxTexture;

import lime.utils.Float32Array;
import lime.utils.UInt32Array;
import lime.utils.UInt16Array;
import lime.utils.Int16Array;
import lime.utils.Int8Array;
import lime.utils.UInt8ClampedArray;
import lime.utils.ArrayBufferView;
import lime.math.Vector2;
import lime.graphics.Image;
import lime.system.Endian;
import lime.system.ThreadPool;
import lime.utils.Assets;

import openfl.geom.Vector3D;
import openfl.geom.Matrix3D;
import openfl.utils.ByteArray;
import openfl.display.BitmapData;
import openfl.display3D.textures.Texture;

@dox(hide)
@:noCompletion #if !foxlite_polymod abstract #else class #end AccessorComponentType #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final BYTE = 5120;
	public inline static final UNSIGNED_BYTE = 5121;
	public inline static final SHORT = 5122;
	public inline static final UNSIGNED_SHORT = 5123;
	public inline static final UNSIGNED_INT = 5125;
	public inline static final FLOAT = 5126;
}

@dox(hide)
@:noCompletion #if !foxlite_polymod abstract #else class #end BufferViewTarget #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final ARRAY_BUFFER = 34962;
	public inline static final ELEMENT_ARRAY_BUFFER = 34963;
}

@dox(hide)
@:noCompletion #if !foxlite_polymod abstract #else class #end PrimitiveMode #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final POINTS = 0;
	public inline static final LINES = 1;
	public inline static final LINE_LOOP = 2;
	public inline static final LINE_STRIP = 3;
	public inline static final TRIANGLES = 4;
	public inline static final TRIANGLE_STRIP = 5;
	public inline static final TRIANGLE_FAN = 6;
}

@dox(hide)
@:noCompletion #if !foxlite_polymod abstract #else class #end SamplerMagFilter #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final NEAREST = 9728;
	public inline static final LINEAR = 9729;
}

@dox(hide)
@:noCompletion #if !foxlite_polymod abstract #else class #end SamplerMinFilter #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final NEAREST = 9728;
	public inline static final LINEAR = 9729;
	public inline static final NEAREST_MIPMAP_NEAREST = 9984;
	public inline static final LINEAR_MIPMAP_NEAREST = 9985;
	public inline static final NEAREST_MIPMAP_LINEAR = 9986;
	public inline static final LINEAR_MIPMAP_LINEAR = 9987;
}

@dox(hide)
@:noCompletion #if !foxlite_polymod abstract #else class #end SamplerWrap #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final CLAMP_TO_EDGE = 33071;
	public inline static final MIRRORED_REPEAT = 33648;
	public inline static final REPEAT = 10497;
}

typedef GLTFData = {
	meshes:Array<FoxMesh>, 
	?materials:Map<String, FoxMaterial>, 
	?animations:Map<String, FoxAnimation>, 
	?skins:Array<FoxSkinData>,
	gltf:Dynamic,
	scenes:Array<FoxObjectGroup>
}

class FoxGLTFLoader {

	/**
		Loads models, animations and lights from a `.gltf` file, this also includes the `.bin` buffers and textures.

		GLTF models are scenes, this means they have an unique structure models should follow.

		You can use the meshes array, but all meshes will be positioned at the origin. Instead, use the `scenes` property.
		This contains parsed `FoxObjectGroup`s containing the respective objects with
		their respective parent, skin data, animations and so on

		__Note:__ Cache is applied only to foxlite resources such as textures, materials and so on. The gltf aswell as
		its binary buffers will be loaded every time you call this function to refresh the cache if something is missing.
	**/
	public static function load(name:String, ?extraShaderFlags:Array<String>, ?customShaderPath:String):GLTFData {
		var dir:String = Path.directory(name) + '/';

		var gltfJson:Dynamic = FoxLoaderUtil.loadJSON(name);
		if(gltfJson == null) {
			FoxLog.warning('FoxGLTFLoader', 'Could not load $name (Not found.)');
			return null;
		}
		if(gltfJson.asset.version == null || gltfJson.asset.version < "2.0") {
			FoxLog.warning('FoxGLTFLoader', 'GLTF version < 2.0 is not supported! ($name)');
			return null;
		}
		gltfJson.assetsKey = name;
		
		var buffers:Array<ByteArray> = [];
		if(gltfJson.buffers != null) for(i=>buf in (gltfJson.buffers:Array<Dynamic>)) {
			var isDataUrl = StringTools.startsWith(buf.uri, "data:");
			var bufPath = isDataUrl ? buf.uri : StringTools.urlDecode(FoxLoaderUtil.filePath(dir + buf.uri));

			var buffer:ByteArray = null;
			if(!isDataUrl) {
				if(!Assets.exists(bufPath)) {
					buffers.push(null);
					FoxLog.warning('FoxGLTFLoader', 'Buffer $i not found! (Loading: $bufPath)');
					continue;
				}
				buffer = Assets.getBytes(bufPath);
				if(buffer == null) {
					FoxLog.warning('FoxGLTFLoader', 'Could not load buffer $i! (Loading: $bufPath)');
					buffers.push(null);
					continue;
				}
			}
			else { // Load embedded
				var bytes:Bytes = Base64.decode(bufPath.split(',')[1]); 
				buffer = ByteArray.fromBytes(bytes);
			}
			buffers.push(buffer);
		}

		if(buffers.length != 0 && buffers.filter(f -> f == null).length == buffers.length) {
			FoxLog.warning('FoxGLTFLoader', 'Could not load "$name". (All buffers are missing)');
			return null;
		}

		var data = _processData(name, gltfJson, buffers, extraShaderFlags, customShaderPath);
		for(b in buffers) b.clear(); // Free memory
		return data;
	}

	/**
		Loads models, animations and lights from a GLTF binary file `.glb`. This method is identical to `load()`

		__Note:__ Cache is applied only to foxlite resources such as textures, materials and so on. The gltf aswell as
		its binary buffers will be loaded every time you call this function to refresh the cache if something is missing.
	**/
	public static function loadBinary(name:String, ?extraShaderFlags:Array<String>, ?customShaderPath:String):GLTFData {
		var path = FoxLoaderUtil.filePath(name);
		if(!Assets.exists(path)) {
			FoxLog.warning('FoxGLTFLoader', 'Could not load "$name" (Not found.)');
			return null;
		}
		
		var glb:ByteArray = Assets.getBytes(path);
		if(glb == null) {
			FoxLog.warning('FoxGLTFLoader', 'Could not load "$name" (Load error.)');
			return null;
		}

		// GLB header checks
		if(glb.readUTFBytes(4) != "glTF") {
			FoxLog.warning('FoxGLTFLoader', 'GLB header error! ($name)');
			return null;
		}
		if(glb.readUnsignedInt() < 2) {
			FoxLog.warning('FoxGLTFLoader', 'GLTF version < 2.0 is not supported! ($name)');
			return null;
		}

		// JSON + Binary buffers
		var length:UInt = glb.readUnsignedInt();
		var jsonLength:UInt = glb.readUnsignedInt();
		glb.position += 4; // Skip JSON header

		if(glb.bytesAvailable < jsonLength) {
			FoxLog.warning('FoxGLTFLoader', 'Could not load "$name". Not enough bytes for json chunk. (${glb.bytesAvailable} < $jsonLength)');
			return null;
		}

		var gltfJson:Dynamic = Json.parse(glb.readUTFBytes(jsonLength));
		
		var binLength:UInt = glb.readUnsignedInt(); // embedded .bin size
		glb.position += 4; // Skip BIN header

		if(glb.bytesAvailable < binLength) {
			FoxLog.warning('FoxGLTFLoader', 'Could not load "$name". Not enough bytes for binary buffer. (${glb.bytesAvailable} < $binLength)');
			return null;
		}

		var dataArray = Bytes.alloc(binLength);
		glb.readBytes(dataArray, 0, binLength);

		var buffers:Array<ByteArray> = [dataArray];

		var data = _processData(name, gltfJson, buffers, extraShaderFlags, customShaderPath);
		
		for(b in buffers) b.clear(); // Free memory
		return data;
	}

	@:noCompletion public static function _processData(name:String, gltfJson:Dynamic, buffers:Array<ByteArray>, ?extraShaderFlags:Array<String>, ?customShaderPath:String):GLTFData {
		var directory = Path.directory(name) + '/';
		if(extraShaderFlags == null) extraShaderFlags = [];
		if(customShaderPath == null) customShaderPath = FoxShader.BASIC;

		var accessors:Array<Dynamic> = gltfJson.accessors;
		var bufferViews:Array<Dynamic> = gltfJson.bufferViews;

		var meshes:Array<FoxMesh> = FoxCache.meshes().get(name) ?? [];
		var materials:Map<String, FoxMaterial> = FoxCache.materialLibs().get(name);
		var textures:Array<FoxTexture> = [];
		var materialArray:Array<FoxMaterial> = [];

		function addFlag(f:String) {
			if(!extraShaderFlags.contains(f)) extraShaderFlags.push(f);
		}

		// Preload
		if(gltfJson.textures != null) for(tex in (gltfJson.textures:Array<Dynamic>)) {
			var image:Dynamic = gltfJson.images[tex.source];

			var isBuffer = Std.isOfType(image?.bufferView, Int);
			var isDataUrl = image?.uri != null && StringTools.startsWith(image.uri, "data:");
			
			if(image?.uri != null || isBuffer) {
				var sampler:Dynamic = gltfJson.samplers[tex.sampler];
				
				var mipmaps:Bool = 
					!(sampler.minFilter == SamplerMinFilter.LINEAR || 
					sampler.minFilter == SamplerMinFilter.NEAREST);

				var params = {
					wrapMode: FoxWrapMode.REPEAT,
					filter: sampler.magFilter == SamplerMagFilter.NEAREST ? FoxTextureFilter.NEAREST : FoxTextureFilter.LINEAR,
					mipFilter: switch(sampler.minFilter:Int) {
						case SamplerMinFilter.LINEAR_MIPMAP_LINEAR,
							 SamplerMinFilter.LINEAR_MIPMAP_NEAREST:
							 	FoxMipFilter.MIPLINEAR;
						case SamplerMinFilter.NEAREST_MIPMAP_LINEAR,
							 SamplerMinFilter.NEAREST_MIPMAP_NEAREST:
							 	FoxMipFilter.MIPNEAREST;
						default: FoxMipFilter.MIPNONE;
					}
				};

				if(sampler.wrapS != null && sampler.wrapT != null) {
					var repeatU = sampler.wrapS != SamplerWrap.CLAMP_TO_EDGE;
					var repeatV = sampler.wrapT != SamplerWrap.CLAMP_TO_EDGE;
					
					if(repeatU && repeatV) params.wrapMode = FoxWrapMode.REPEAT;
					else if(repeatU) params.wrapMode = FoxWrapMode.REPEAT_U_CLAMP_V;
					else if(repeatV) params.wrapMode = FoxWrapMode.CLAMP_U_REPEAT_V;
					else params.wrapMode = FoxWrapMode.CLAMP;
				}

				image.name = name + ':' + (image.name ?? 'Image_${tex.source+1}');

				var texture:FoxTexture = null;
				if(!isBuffer) {
					var imagePath = isDataUrl ? image.uri : StringTools.urlDecode(FoxLoaderUtil.filePath(directory + Std.string(image.uri)));
					texture = FoxTexture.fromImageRaw(imagePath, mipmaps, cast 1, params) ?? FoxRenderer.MISSING_TEXTURE;
				}
				else if(!FoxCache.textures().exists(image.name)) {
					texture = new FoxTexture();
					texture.assetsKey = image.name;
					texture.wrapMode = params.wrapMode;
					texture.filter = params.filter;
					texture.mipFilter = params.mipFilter;

					#if foxlite_verbose
					FoxLog.log("FoxGLTFLoader", "Add buffer texture to cache: " + texture.assetsKey);
					#end
					FoxCache.textures().set(image.name, texture);

					var view = bufferViews[image.bufferView];
					var buffer = buffers[view.buffer];
					var imageBytes = Bytes.alloc(view.byteLength);
					imageBytes.blit(0, buffer, view.byteOffset, view.byteLength);

					function onImageLoaded(image:Image) {
						(imageBytes:ByteArray).clear();
						if(image == null) return;

						trace("[FoxLite > FoxGLTFLoader]: Add buffer texture to cache: " + texture.assetsKey);

						// Upload image directly to the GPU
						// This method is completely detached from openfl's BitmapData operations
						// Unless we find a better method, we'll stick with this
						function task() {
							texture.glTexture = FoxRenderer.createTextureStorage(image.width, image.height, image.transparent ? "rgba" : "rgb");
							(cast texture.glTexture:Texture).uploadFromTypedArray(image.buffer.data);
						}
						
						if(FoxRenderer.forceSyncLoading)
							task();
						else 
							FoxRenderer.runTaskAtNextDraw(task);
					}

					function onImageError(e:Dynamic) {
						trace('[Foxlite > FoxGLTFLoader]: Could not create buffer texture: ${image.name} ($e)');
						FoxCache.textures().remove(image.name);
					}
					
					// If we're on the main thread, load it async, else lime's own thread pool system clashes with itself (bruh)
					if(ThreadPool.isMainThread() && !FoxRenderer.forceSyncLoading) {
						var future = Image.loadFromBytes(imageBytes);
						future.onComplete(onImageLoaded);
						future.onError(onImageError);
					}
					else
						onImageLoaded(Image.fromBytes(imageBytes));
				}
				else texture = FoxCache.textures().get(directory + image.name);
				textures.push(texture);
			}
			else textures.push(null);
		}

		if(gltfJson.materials != null && materials == null) {
			materials = new StringMap();
			for(idx=>mat in (gltfJson.materials:Array<Dynamic>)) {
				if(!Std.isOfType(mat.name, String)) mat.name = 'Material.${StringTools.lpad(Std.string(idx), '0', 3)}';
				var material:FoxMaterial = materials?.get(mat.name);

				if(material != null) {
					materialArray.push(material);
					continue;
				}

				material = new FoxMaterial();
				material.assetsKey = mat.name;
				if(Std.isOfType(mat.doubleSided, Bool)) material.culling = mat.doubleSided ? FoxTriangleFace.NONE : FoxTriangleFace.BACK;
				
				if(Std.isOfType(mat.alphaMode, String)) switch(mat.alphaMode:String) {
					case "OPAQUE": addFlag("NO_ALPHA_SCISSOR");
					case "BLEND": material.blendMode = FoxBlendMode.MIX;
					case "MASK": material.alphaScissor = 0.5;
				}

				if(Std.isOfType(mat.alphaCutoff, Float) || Std.isOfType(mat.alphaCutoff, Int))
					material.alphaScissor = mat.alphaCutoff;

				if(mat.alphaMode == "BLEND" && material.alphaScissor <= 0)
					material.alphaScissor = 0.05;
				
				if(mat.emissiveTexture != null) {
					addFlag("EMISSIVE_MAP");
					var tex = textures[mat.emissiveTexture.index];
					if(tex != null) material.textures.set("emissiveMap", tex);
				}

				if(Std.isOfType(mat.emissiveFactor, Array)) {
					var f:Array<Float> = mat.emissiveFactor;
					material.params.set("uEmissive", f.copy());
				}
				else material.params.set("uEmissive", [0, 0, 0]);

				if(mat.normalTexture != null) {
					addFlag("NORMAL_MAP");
					var tex = textures[mat.normalTexture.index];
					if(tex != null) material.textures.set("normalMap", tex);
				}

				var pbr:Dynamic = mat.pbrMetallicRoughness;

				material.setMetallic(pbr?.metallicFactor ?? 1);
				material.setRoughness(pbr?.roughnessFactor ?? 1);

				if(pbr?.baseColorFactor != null) {
					var c = pbr?.baseColorFactor;
					material.params.set("color", c);
				}

				if(pbr?.metallicRoughnessTexture != null) {
					addFlag("ORM_MAP");
					var tex = textures[pbr.metallicRoughnessTexture.index];
					if(tex != null) material.textures.set("ormMap", tex);
				}

				if(pbr?.baseColorTexture != null) {
					var tex = textures[pbr.baseColorTexture.index];
					if(tex != null) material.textures.set("bitmap", tex);
					extraShaderFlags.remove("SOLID");
				}
				else addFlag("SOLID");

				// Extensions
				var KHR_materials_specular:Dynamic = mat.extensions?.KHR_materials_specular;
				var KHR_materials_emissive_strength:Dynamic = mat.extensions?.KHR_materials_emissive_strength;
				var KHR_materials_unlit:Dynamic = mat.extensions?.KHR_materials_unlit;

				if(KHR_materials_unlit != null) addFlag("UNSHADED");

				if(KHR_materials_specular?.specularColorFactor != null) {
					var spec = KHR_materials_specular.specularColorFactor;
					material.setSpecularLevels(spec[0], spec[1], spec[2]);
				}

				var hasEmissiveStrength = Std.isOfType(KHR_materials_emissive_strength?.emissiveStrength, Float) || Std.isOfType(KHR_materials_emissive_strength?.emissiveStrength, Int);
				var em = material.params.get("uEmissive");
				if(em != null) {
					if(hasEmissiveStrength) {
						var s:Float = KHR_materials_emissive_strength.emissiveStrength;
						em[0] *= s;
						em[1] *= s;
						em[2] *= s;
					}
				}

				// Compile shader
				material.shader = FoxShader.fromAsset(customShaderPath, extraShaderFlags);

				materials.set(mat.name, material);
				materialArray.push(material);
			}
			FoxCache.materialLibs().set(name, materials);
		}
		else if(materials != null) for(m in materials) materialArray.push(m);

		if(meshes.length == 0 && gltfJson.meshes != null) {
			for(mesh in (gltfJson.meshes:Array<Dynamic>)) {
				for(i=>prim in (mesh.primitives:Array<Dynamic>)) {
					var mesh = new FoxMesh();
					var meshAttributes:IntMap<String> = new IntMap();
					var skip = false;

					for(attrib in Reflect.fields(prim.attributes)) meshAttributes.set(Reflect.field(prim.attributes, attrib), attrib.toUpperCase());
					meshAttributes.set(prim.indices, "INDICES");
					
					for(attribIndex=>attrib in meshAttributes) {
						var accessor:Dynamic = accessors[attribIndex];
						var view:Dynamic = bufferViews[accessor.bufferView];
						var buffer:ByteArray = buffers[view.buffer];
						if(buffer == null && accessor.sparse == null) {
							FoxLog.warning('Buffer ${view.buffer} not found for mesh $i/$attrib, skipping!');
							skip = true;
							break;
						}

						var count:Int = accessor.count;
						var dataPerVertex:Int = switch(accessor.type:String) {
							case "SCALAR": 1;
							case "VEC2": 2;
							case "VEC3": 3;
							case "VEC4", "MAT2": 4;
							case "MAT3": 9;
							case "MAT4": 16;
							default: 1;
						};
						count *= dataPerVertex;

						var bufferType:Null<Int> = switch(attrib) {
							case "POSITION": FoxVertexBufferType.VERTICES;
							case "NORMAL": FoxVertexBufferType.NORMALS;
							case "TANGENT": FoxVertexBufferType.TANGENTS;
							case "TEXCOORD_0": FoxVertexBufferType.UVS;
							case "JOINTS_0": FoxVertexBufferType.BONE_INDICES;
							case "WEIGHTS_0": FoxVertexBufferType.WEIGHTS;
							case "COLOR_0": FoxVertexBufferType.COLORS;
							case "INDICES": FoxVertexBufferType.INDICES;
							default: continue;
						}

						var dataArray:ArrayBufferView = switch(accessor.componentType:Int) {
							case AccessorComponentType.BYTE: new Int8Array(#if js count #else null, buffer #end);
							case AccessorComponentType.UNSIGNED_BYTE: new UInt8ClampedArray(#if js count #else null, buffer #end);
							case AccessorComponentType.SHORT: new Int16Array(#if js count #else null, buffer #end);
							case AccessorComponentType.UNSIGNED_SHORT: new UInt16Array(#if js count #else null, buffer #end);
							case AccessorComponentType.UNSIGNED_INT: new UInt32Array(#if js count #else null, buffer #end);
							case AccessorComponentType.FLOAT: new Float32Array(#if js count #else null, buffer #end);
							default: null;
						}

						var stride:Int = switch(accessor.componentType:Int) {
							case AccessorComponentType.SHORT,
								 AccessorComponentType.UNSIGNED_SHORT: 2;
							case AccessorComponentType.UNSIGNED_INT,
								 AccessorComponentType.FLOAT: 4;
							default: 1;
						}

						// Write data
						#if js

						var blitBuffer:Bytes = Bytes.ofData(dataArray.buffer);
						if(buffer != null) blitBuffer.blit(0, buffer, (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0), dataArray.byteLength);

						#else

						// Native doesn't need blitting, we can just use the buffer pointer
						dataArray.byteLength = count * stride;
						dataArray.length = count;
						dataArray.byteOffset = (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0);
						
						#end

						if(accessor.sparse != null) {
							trace('Sparse not implemented yet.');
						}
						
						var gpuBuffer:FoxVertexBuffer = attrib == "INDICES" ? new FoxIndexBuffer(accessor.count, dataPerVertex) : new FoxVertexBuffer(accessor.count, dataPerVertex);
						gpuBuffer.uploadFromTypedArray(dataArray);
						if(accessor.normalized == true) gpuBuffer.normalized = true;
						mesh.buffers[bufferType] = gpuBuffer;

						if(mesh.bounds == null && attrib == "POSITION") {
							// Add precalculated bounds aswell
							var min:Array<Float> = accessor.min;
							var max:Array<Float> = accessor.max;
							mesh.bounds = new BoundingBox();
							mesh.bounds.fromExtents(
								new Vector3D(min[0], min[1], min[2]),
								new Vector3D(max[0], max[1], max[2])
							);
						}
					}
					if(skip) break;
					if(Std.isOfType(prim.material, Int)) mesh.material = materialArray[prim.material];
					// TODO: maybe move render mode to mesh instead of material?
					//if(Std.isOfType(prim.mode, Int)) ;
					meshes.push(mesh);
				}
			}
			FoxCache.meshes().set(name, meshes);
		}
		
		var nodes:Array<Dynamic> = gltfJson.nodes;
		var parent:Array<Null<Int>> = [];
		parent.resize(nodes.length);

		// Cache parent indices
		for(i=>node in nodes) if(Std.isOfType(node.children, Array)) for(c in (node.children:Array<Int>)) {
			if(parent[c] != null) FoxLog.warning('Node ${parent[c]} ($c) already has a parent!');
			parent[c] = i;
		}

		var skins:Array<FoxSkinData> = FoxCache.skins().get(name) ?? [];
		// Skinning
		if(gltfJson.skins != null && skins.length == 0) {
			// Temporary vectors for Quaternion -> Euler conversion
			#if foxlite_polymod
			var tempMatrix = new Matrix3D();
			var tempVectors = tempMatrix.decompose().__array;
			#end
			for(skin in (gltfJson.skins:Array<Dynamic>)) {
				var accessor:Dynamic = null;
				var view:Dynamic = null;
				var buffer:ByteArray = null;

				var inverseMat:Matrix3D = null;

				// inverseBindMatrices can be optional
				if(skin.inverseBindMatrices != null) {
					accessor = accessors[skin.inverseBindMatrices];
					view = bufferViews[accessor.bufferView];
					buffer = buffers[view.buffer];
				}
				else inverseMat = new Matrix3D();

				var skinData = new FoxSkinData();

				var gltfJoints:Array<Int> = skin.joints;
				for(idx=>joint in gltfJoints) {
					if(skin.inverseBindMatrices != null) {
						inverseMat = new Matrix3D();
						var a = inverseMat.rawData.__array;
						for(i in 0...16) {
							buffer.position = view.byteOffset + (i+idx*16)*4;
							a[i] = buffer.readFloat();
						}
					}
					var bone = new FoxBone(inverseMat);
					var node:Dynamic = nodes[joint];
					bone.name = node.name;
					if(Std.isOfType(node.translation, Array)) bone.setPosition(node.translation[0], node.translation[1], node.translation[2]);
					if(Std.isOfType(node.scale, Array)) bone.setScale(node.scale[0], node.scale[1], node.scale[2]);
					if(Std.isOfType(node.rotation, Array)) {
						#if foxlite_polymod
						// Rotations are stored as quaternions, we have to turn them into euler angles
						tempVectors[1].setTo(node.rotation[0], node.rotation[1], node.rotation[2]);
						tempVectors[1].w = node.rotation[3];

						tempMatrix.recompose(tempVectors, cast 2);
						FoxMathUtil.eulerFromMatrix(tempMatrix, bone.rotation);
						#else
						bone.rotation.setTo(node.rotation[0], node.rotation[1], node.rotation[2]);
						bone.rotation.w = node.rotation[3];
						FoxMathUtil.eulerFromQuaternion(bone.rotation, bone.rotation);
						#end
					}
					skinData.addBone(bone, -1);
					skinData.reparentBoneByName(idx, nodes[parent[joint]]?.name ?? "");
				}
				skins.push(skinData);
			}
			FoxCache.skins().set(name, skins);
		}

		var animations:StringMap<FoxAnimation> = FoxCache.animationLibs().get(name);

		if(gltfJson.animations != null && animations == null) {
			animations = new StringMap();
			for(anim in (gltfJson.animations:Array<Dynamic>)) {
				var animation = new FoxAnimation(anim.name);
				var trackType:FoxTrackType = -1;
				for(channel in (anim.channels:Array<Dynamic>)) {
					var sampler:Dynamic = anim.samplers[channel.sampler];
					var interpolation:FoxEaseType = sampler.interpolation == "STEP" ? FoxEaseType.ZERO : FoxEaseType.LINEAR;
					var node:Dynamic = nodes[channel.target.node];
					var path:String = channel.target.path;

					var accessorIn:Dynamic = accessors[sampler.input];	// Times
					var accessorOut:Dynamic = accessors[sampler.output]; // Values

					var viewIn:Dynamic = bufferViews[accessorIn.bufferView];
					var viewOut:Dynamic = bufferViews[accessorOut.bufferView];

					var bufferIn:ByteArray = buffers[viewIn.buffer];
					var bufferOut:ByteArray = buffers[viewOut.buffer];

					if(bufferIn == null || bufferOut == null) {
						FoxLog.warning('Buffers ${viewIn.buffer} and/or ${viewOut.buffer} not found for animation track "${node.name}:$path", skipping!');
						if(viewIn.buffer == viewOut.buffer) break;
						else continue;
					}

					animation.duration = Math.max(animation.duration, accessorIn.max[0]);

					trackType = switch(accessorOut.type:String) {
						case "SCALAR": FoxTrackType.FLOAT;
						case "VEC2": FoxTrackType.VECTOR2;
						case "VEC3": FoxTrackType.VECTOR3D;
						case "VEC4": path == "rotation" ? FoxTrackType.QUATERNION : FoxTrackType.VECTOR4;
						//case "MAT2": FoxTrackType.MATRIX2;
						//case "MAT3": FoxTrackType.MATRIX3;
						case "MAT4": FoxTrackType.MATRIX4;
						default: continue;
					};

					var stride:Int = switch(accessorOut.componentType:Int) {
						case AccessorComponentType.SHORT,
							 AccessorComponentType.UNSIGNED_SHORT: 2;
						case AccessorComponentType.UNSIGNED_INT,
							 AccessorComponentType.FLOAT: 4;
						default: 1;
					}

					function readValueNorm(pos:Int):Float {
						bufferOut.position = viewOut.byteOffset + pos*stride;
						return switch(accessorOut.componentType:Int) {
							case AccessorComponentType.BYTE: Math.max(bufferOut.readByte() / 127, -1);
							case AccessorComponentType.UNSIGNED_BYTE: bufferOut.readUnsignedByte() / 255;
							case AccessorComponentType.SHORT: Math.max(bufferOut.readShort() / 32767, -1);
							case AccessorComponentType.UNSIGNED_SHORT: bufferOut.readUnsignedShort() / 65535;
							default: bufferOut.readFloat();
						}
					}
					
					path = StringTools.replace(path, "translation", "position");
					path = StringTools.replace(path, "rotation", "quaternion"); // We'll be using quat interpolation
					var track:FoxAnimationTrack<Any> = animation.addTrack('${node.name}:$path', trackType);
					var outPos:Int = 0;
					for(i in 0...accessorIn.count) {
						bufferIn.position = viewIn.byteOffset + i*4;
						var time:Float = bufferIn.readFloat();
						switch(trackType) {
							case FoxTrackType.FLOAT: {
								track.addFrame(time, readValueNorm(outPos++), interpolation);
							};
							case FoxTrackType.VECTOR2: {
								var x = readValueNorm(outPos++);
								var y = readValueNorm(outPos++);
								track.addFrame(time, new Vector2(x, y), interpolation);
							};
							case FoxTrackType.VECTOR3D: {
								var x = readValueNorm(outPos++);
								var y = readValueNorm(outPos++);
								var z = readValueNorm(outPos++);
								track.addFrame(time, new Vector3D(x, y, z), interpolation);
							};
							case FoxTrackType.VECTOR4, FoxTrackType.QUATERNION: {
								var v = new Vector3D(
									readValueNorm(outPos++),
									readValueNorm(outPos++),
									readValueNorm(outPos++),
									readValueNorm(outPos++)
								);
								track.addFrame(time, v, interpolation);
							};
							case FoxTrackType.MATRIX4: {
								var matrix = new Matrix3D();
								var a = matrix.rawData.__array;
								for(i in 0...16) a[i] = readValueNorm(outPos++);
								track.addFrame(time, matrix, interpolation);
							};
						}
					}
				}

				animations.set(anim.name, animation);
			}
			FoxCache.animationLibs().set(name, animations);
		}

		var data:GLTFData = {
			meshes: meshes,
			materials: materials,
			skins: skins,
			animations: animations,
			gltf: gltfJson,
			scenes: null
		};
		data.scenes = buildScenes(data);

		return data;
	}

	/**
		Builds `FoxObjectGroup`s containing models, meshes and lights from GLTF data
	**/
	public static function buildScenes(gltf:GLTFData):Array<FoxObjectGroup> {
		var groups:Array<FoxObjectGroup> = [];
		if(gltf?.gltf == null) return groups;
		var nodes:Array<Dynamic> = gltf.gltf.nodes;
		var skins:Array<Dynamic> = gltf.gltf.skins ?? [];
		var scenes:Array<Dynamic> = gltf.gltf.scenes;
		// For lights
		var KHR_lights_punctual:Dynamic = gltf.gltf.extensions?.KHR_lights_punctual;

		// Skinned meshes, animations and objects
		var armatures:Array<FoxArmature> = skins.map(f -> new FoxArmature());
		var linkMapping:IntMap<FoxObject> = new IntMap();
		
		if(scenes != null) for(idx=>scene in scenes) {
			var group = new FoxObjectGroup();
			group.name = scene.name;

			function process(node:Dynamic, parent:FoxObjectGroup, nodeIndex:Int) {
				if(skins.filter(j -> j.joints[0] == nodeIndex).length != 0) return; // Don't walk bone structures (already built)

				var parentGroup:FoxObjectGroup = parent;
				if(node.mesh != null) {
					var model = new FoxModel();
					model.name = node.name;
					model.meshes = [gltf.meshes[node.mesh]];
					if(Std.isOfType(node.translation, Array)) model.setPosition(node.translation[0], node.translation[1], node.translation[2]);
					if(Std.isOfType(node.rotation, Array)) model.setRotationQuaternion(node.rotation[0], node.rotation[1], node.rotation[2], node.rotation[3]);
					if(Std.isOfType(node.scale, Array)) model.setScale(node.scale[0], node.scale[1], node.scale[2]);
					if(node.skin != null) {
						// Add to the armature parent instead
						var armature = armatures[node.skin];
						armature.skin = gltf.skins[node.skin];
						armature.add(model);
						parent.add(armature); // Add to group once
					}
					else parent.add(model);
					linkMapping.set(nodeIndex, model);
				}
				else if(node.extensions?.KHR_lights_punctual != null) {
					var lightData = KHR_lights_punctual.lights[node.extensions?.KHR_lights_punctual.light];
					var light:FoxBaseLight = switch(lightData.type) {
						case "directional": new FoxDirectionalLight();
						case "point": new FoxPointLight();
						case "spot": new FoxSpotLight(0, 0, 0, 0xFFFFFFFF, 1, 5, 1, lightData.outerConeAngle * FoxMathUtil.radToDeg);
						default: null;
					}
					if(light != null) {
						if(Std.isOfType(lightData?.color, Array)) light.color.setTo(lightData.color[0], lightData.color[1], lightData.color[2]);
						if(Std.isOfType(node.translation, Array)) light.setPosition(node.translation[0], node.translation[1], node.translation[2]);
						if(Std.isOfType(node.rotation, Array)) light.setRotationQuaternion(node.rotation[0], node.rotation[1], node.rotation[2], node.rotation[3]);
						light.name = node.name;
						parent.add(light);
						linkMapping.set(nodeIndex, light);
					}
				}
				else {
					parentGroup = new FoxObjectGroup();
					parentGroup.name = node.name;
					if(Std.isOfType(node.translation, Array)) parentGroup.setPosition(node.translation[0], node.translation[1], node.translation[2]);
					if(Std.isOfType(node.rotation, Array)) parentGroup.setRotationQuaternion(node.rotation[0], node.rotation[1], node.rotation[2], node.rotation[3]);
					if(Std.isOfType(node.scale, Array)) parentGroup.setScale(node.scale[0], node.scale[1], node.scale[2]);
					parent.add(parentGroup);
					linkMapping.set(nodeIndex, parentGroup);
				}

				if(node.children != null) for(c in (node.children:Array<Dynamic>)) {
					var child:Dynamic = nodes[c];
					process(child, parentGroup, c);
				}
			}
			
			if(scene.nodes != null) for(sceneNode in (scene.nodes:Array<Dynamic>)) {
				process(nodes[sceneNode], group, sceneNode);
			}

			var animations:Array<Dynamic> = gltf.gltf.animations;

			if(animations != null) { // Map animations
				var player = new FoxAnimationPlayer(gltf.animations);
				group.animation = player;

				for(anim in animations) for(channel in (anim.channels:Array<Dynamic>)) {
					var object = linkMapping.get(channel.target.node);
					if(object == null) continue;
					var trackName = object.name;
					player.linkObject(trackName, object);
				}
				for(skin in gltf.skins) player.linkSkin(skin);
			}
			groups.push(group);
		}
		return groups;
	}
}