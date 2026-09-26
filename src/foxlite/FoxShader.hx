
package foxlite;

import EReg;
import StringTools;
import foxlite.FoxCache;
import foxlite.loaders.FoxLoaderUtil;
import foxlite.renderer.FoxRenderer;
import foxlite.system.Float32BufferCache;
import foxlite.system.Int32BufferCache;
import foxlite.texture.FoxTexture;
import haxe.ds.StringMap;
import lime.graphics.WebGLRenderContext;
import lime.math.Vector2;
import lime.utils.Float32Array;
import lime.utils.Assets;
import openfl.display3D.Context3D;
import openfl.display3D.Program3D;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;
#if foxlite_polymod
import lime.graphics.opengl.GL;
import lime.utils.DataPointer;
#end

// Uniform constant types for switch statement
@:dox(hide) #if !foxlite_polymod abstract #else class #end UType #if !foxlite_polymod (Int) from Int to Int #end {
	public inline static final FLOAT = 0x1406;
	public inline static final FLOAT_VEC2 = 0x8B50;
	public inline static final FLOAT_VEC3 = 0x8B51;
	public inline static final FLOAT_VEC4 = 0x8B52;
	public inline static final FLOAT_MAT2 = 0x8B5A;
	public inline static final FLOAT_MAT3 = 0x8B5B;
	public inline static final FLOAT_MAT4 = 0x8B5C;
	public inline static final INT = 0x1404;
	public inline static final INT_VEC2 = 0x8B53;
	public inline static final INT_VEC3 = 0x8B54;
	public inline static final INT_VEC4 = 0x8B55;
	public inline static final BOOL = 0x8B56;
	public inline static final BOOL_VEC2 = 0x8B57;
	public inline static final BOOL_VEC3 = 0x8B58;
	public inline static final BOOL_VEC4 = 0x8B59;
	public inline static final SAMPLER_2D = 0x8B5E;
}

#if !foxlite_polymod
typedef FoxShaderTextureInput = {location:Int, value:FoxTexture};
typedef FoxUniformCache = {location:Int, type:Int, size:Int};
#end

class FoxShader {

	public inline static final BASIC:String = "foxlite/basic";
	public inline static final MINIMAL:String = "foxlite/minimal";
	public inline static final SKY:String = "foxlite/sky_panorama";

	public inline static final PRAGMA_FOXFLAGS = "#pragma foxflags";
	public inline static final PRAGMA_SHADOW_PROGRAM = "#pragma shadow_program_check";
	public inline static final PRAGMA_OPENGL3 = "#pragma opengl3";
	public inline static final PRAGMA_OPENGL4 = "#pragma opengl4";

	// Based on OpenGL 3.2
	// https://github.com/mattdesl/lwjgl-basics/wiki/GLSL-Versions
	public inline static final OPENGL3_VERSION = "#version 150"; 
	public inline static final OPENGL3_VERSION_ES = "#version 300 es"; 

	// Only available in desktop platforms
	public inline static final OPENGL4_VERSION = "#version 450"; 

	public static var GLOBAL_FLAGS:Array<String> = [];

	var context:Context3D;
	var gl:#if lime WebGLRenderContext #else Dynamic #end;

	/**
		Version of the shader for the shadow pass only
	**/
	public var shadow:FoxShader; 
 
	public var assetsKey:String;
	public var program:Program3D;
	public var textureInput:Map<String, FoxShaderTextureInput> = new StringMap();
	public var uniformCache:Map<String, FoxUniformCache> = new StringMap();
	public final attribIdx = {
		position: -1,
		texCoord: -1,
		normal: -1,
		tangent: -1,
		color: -1,
		boneWeight: -1,
		boneIndex: -1,
		instanceData: {
			data0: -1,
			data1: -1,
			data2: -1,
			color: -1
		}
	};

	/**
		Cached skin location for fast access
	**/
	public var __uSkinnedLocation:Int = -1;

	/**
		Cached bone data location for fast access
	**/
	public var __bonesDataLocation:Int = -1;
	public var __bonesDataSizeLocation:Int = -1;
	public var __prevBonesDataLocation:Int = -1;

	/**
		Cached instanced location for fast access
	**/
	public var __uInstancedLocation:Int = -1;

	public var __hasLights:Bool = false;

	/**
		Variable to keep track of combined shaders
	**/
	public var __isCombined:Bool = false; 

	/**
		When loading a shader, it won't be compiled right away, instead it will
		be compiled when needed for rendering. This should be set only once per shader.

		This is required for async/threaded resource loading, as the programs fail to link
		when in a separate thread (I believe there's a fix to it but I don't know).

		If any uniform is set while this flag is enabled, it will be saved uploaded
		to the GPU once the shader been compiled.
	**/
	public var __needsCompiling:Bool = false;

	public var __fragSource:String;
	public var __vertSource:String;
	/**
		The preprocessor flags for this shader.
	**/
	public var shaderDefines(default, never):Array<String> = [];

	/**
		A temporary array to store matrix values, cached for speed
	**/
	#if !foxlite_polymod
	var __tmpMatrix:Float32Array = new Float32Array(16);
	#end

	public function new():Void {
		context = FoxRenderer.getContext();
		gl = context.gl;
	}

	public static function staticInit() {
		#if foxlite_polymod
		trace(GLOBAL_FLAGS);
		#end
	}

	public static function fromSources(vert:String, frag:String, ?flags:Array<String>, ?output:FoxShader):FoxShader {
		var shader = output ?? new FoxShader();

		// #include preprocessor
		vert = FoxShader.processIncludes(vert);
		frag = FoxShader.processIncludes(frag);

		// ---- Process OPENGL pragma ----
		
		var gl3VersionCode = switch(FoxRenderer.renderContext) {
			case 'OPENGL': OPENGL3_VERSION;
			case 'WEBGL', 'OPENGLES': OPENGL3_VERSION_ES;
			default: "";
		}
		vert = StringTools.replace(vert, PRAGMA_OPENGL3, gl3VersionCode);
		frag = StringTools.replace(frag, PRAGMA_OPENGL3, gl3VersionCode);

		if(FoxRenderer.renderContext == "OPENGL") {
			vert = StringTools.replace(vert, PRAGMA_OPENGL4, OPENGL4_VERSION);
			frag = StringTools.replace(frag, PRAGMA_OPENGL4, OPENGL4_VERSION);
		}
		
		// ---- Process foxlite flags ----

		var vertexID = '#define VERTEX\n';
		var fragmentID = '#define FRAGMENT\n';

		if(flags == null) flags = [];
		else flags = flags.copy();
		
		flags = FoxShader.sanitizeFlags(flags);

		var defs:String = "";
		for(def in flags) defs += '#define $def\n';
			
		vert = StringTools.replace(vert, PRAGMA_FOXFLAGS, vertexID + defs);
		frag = StringTools.replace(frag, PRAGMA_FOXFLAGS, fragmentID + defs);
			
		for(flag in flags) if(!shader.shaderDefines.contains(flag)) shader.shaderDefines.push(flag);

		// Save sources
		// TODO: Save original sources somewhere, so recompile() actually works
		shader.__fragSource = frag;
		shader.__vertSource = vert;
		shader.__needsCompiling = true;

		// Shadow shader
		// TODO: same of the above
		var shadowShader = new FoxShader();
		var shadowCheck = #if !foxlite_polymod FoxShader.PRAGMA_SHADOW_PROGRAM; #else "#pragma shadow_program_check"; #end 
		shadowShader.__fragSource = StringTools.replace(frag, shadowCheck, "#define SHADOW_PASS");
		shadowShader.__vertSource = StringTools.replace(vert, shadowCheck, "#define SHADOW_PASS");
		shadowShader.__needsCompiling = true;
		shader.shadow = shadowShader;

		return shader;
	}

	// TODO: Test further if this code doesn't give any errors/softlocks
	public static function processIncludes(source:String):String {
		var includes = new EReg('((\\/\\/|\\/\\*|\\*)\\s*)*#include\\s+["\'`](.+)["\'`]', "i"); 
		var list = []; // Keep track of what we've imported, also prevents recursive importing
		while(includes.match(source)) {
			var line = includes.matched(0);
			var file = includes.matched(3);

			// Skip if we already included it
			if(list.contains(file)) {
				source = includes.replace(source, "");
				continue;
			}

			// Skip if it's inside a comment
			if(StringTools.startsWith(line, "//") ||
			   StringTools.startsWith(line, "/*") ||
			   StringTools.startsWith(line, "*")
			) {
				source = includes.replace(source, "// Skipped: " + file);
				continue;
			}
			#if foxlite_verbose
			FoxLog.log("FoxShader", "Including shader source: " + file);
			#end

			list.push(file);
			var defPath = FoxLoaderUtil.shaderIncludeRoot(file);
			var cache = FoxCache.shaderIncludes().get(defPath);
			if(cache == null) { // Doesn't exist in cache, try load and add
				cache = FoxLoaderUtil.loadText(defPath);
				// Silly but okay
				if(cache == null) {
					FoxLog.warning('FoxShader', 'FILE NOT FOUND: $defPath');
					cache = '// MISSING SOURCE: "$file" ($defPath)';
				}
				else FoxCache.shaderIncludes().set(defPath, cache);
			}
			source = includes.replace(source, cache);
		}
		return source;
	}

	public static function fromAsset(name:String, ?flagsDefs:Array<String>):FoxShader {
		var flags:Array<String> = [];
		if(flagsDefs != null) flags = FoxShader.sanitizeFlags(flagsDefs);
		// Javascript removes [ ] when converting an array to string so we add them back
		// We don't use the #if js preprocessor because Polymod has a parsing bug.
		var defHash:String = flags.toString();
		if(!StringTools.startsWith(defHash, '[')) defHash = '[$defHash]';
		if(FoxCache.shaders().exists(name + defHash)) return FoxCache.shaders().get(name + defHash);
		
		var vert:String = FoxLoaderUtil.shaderVert(name);
		var frag:String = FoxLoaderUtil.shaderFrag(name);
		
		if(Assets.exists(vert)) vert = Assets.getText(vert);
		else {
			FoxLog.warning('FoxShader', 'Vertex source not found for $vert');
			vert = "";
		}

		if(Assets.exists(frag)) frag = Assets.getText(frag);
		else {
			FoxLog.warning('FoxShader', 'Fragment source not found for $frag');
			frag = "";
		}

		if(vert == "" && frag == "") return null;

		var shader = FoxShader.fromSources(vert, frag, flags);
		shader.assetsKey = name;
		#if foxlite_verbose
		FoxLog.log("FoxShader", "Add shader to cache: " + name + defHash);
		#end
		FoxCache.shaders().set(name + defHash, shader);
		return shader;
	}

	public static function defineName(name:String):String {
		var rx = new EReg("[^\\w]+|[\\d]+", 'g');
		return rx.replace(name, '_').toUpperCase();
	}

	/**
		Compiles the shader. Used internally. Maybe one day it'll support async.

		While the shader isn't compiled, no uniform should be set, else they will be lost.
	**/
	public function compile() {
		if(program == null) program = context.createProgram(cast 1); // 1 = Context3DProgramFormat.GLSL
		FoxRenderer.uploadFromGLSLProgram3D(program, __vertSource, __fragSource);
		initCache();
		__needsCompiling = false;
	}

	public function initCache() {
		if(program == null) return;
		var glProgram = program.__glProgram;

		program.__glslSamplerNames = [];
		
		gl.useProgram(glProgram); 
		uniformCache.clear();
		var activeUniforms = gl.getProgramParameter(glProgram, gl.ACTIVE_UNIFORMS);
		for(a in 0...activeUniforms) {
			var info = gl.getActiveUniform(glProgram, a);
			var location = gl.getUniformLocation(glProgram, info.name);
			var name = info.name;
			// Sanitize for uniform arrays, but allow struct arrays
			if(StringTools.endsWith(name, "[0]")) name = StringTools.replace(name, "[0]", ""); 

			uniformCache.set(name, {
				location: cast location,
				type: info.type,
				size: info.size
			});

			program.__glslSamplerNames.push(null);
			if(info.type == UType.FLOAT_MAT4) program.__glslSamplerNames[a] = name;
		}
		
		attribIdx.position = gl.getAttribLocation(glProgram, "foxlite_Position");
		attribIdx.texCoord = gl.getAttribLocation(glProgram, "foxlite_TexCoord");
		attribIdx.normal = gl.getAttribLocation(glProgram, "foxlite_Normal");
		attribIdx.tangent = gl.getAttribLocation(glProgram, "foxlite_Tangent");
		attribIdx.color = gl.getAttribLocation(glProgram, "foxlite_Color");
		attribIdx.boneWeight = gl.getAttribLocation(glProgram, "foxlite_BoneWeight");
		attribIdx.boneIndex = gl.getAttribLocation(glProgram, "foxlite_BoneIndex");
		attribIdx.instanceData.data0 = gl.getAttribLocation(glProgram, "foxlite_InstanceData0");
		attribIdx.instanceData.data1 = gl.getAttribLocation(glProgram, "foxlite_InstanceData1");
		attribIdx.instanceData.data2 = gl.getAttribLocation(glProgram, "foxlite_InstanceData2");
		attribIdx.instanceData.color = gl.getAttribLocation(glProgram, "foxlite_InstanceColor");
		__uSkinnedLocation = uniformCache.get("uSkinned")?.location ?? -1;
		__uInstancedLocation = uniformCache.get("uInstanced")?.location ?? -1;
		// Bone data
		__bonesDataLocation = uniformCache.get("BONESDATA")?.location ?? -1;
		__bonesDataSizeLocation = uniformCache.get("BONESDATA_TWIDTH")?.location ?? -1;
		__prevBonesDataLocation = uniformCache.get("PREV_BONESDATA")?.location ?? -1;

		__hasLights = uniformCache.exists("lightCount") && (
				      uniformCache.exists("directionalLights[0].color")
				   || uniformCache.exists("pointLights[0].color")
				   || uniformCache.exists("spotLights[0].color")
				   || uniformCache.exists("areaLights[0].color"));
	}

	/**
	* Handy little function to combine different fragment and vertex programs from two different shaders into one
	* without recompiling sources!
	* 
	* __Note:__ since this shader uses programs from other shaders, `destroy()` won't delete the program on the GPU
	* and destroying `shaderA` or `shaderB` will cause issues when trying to use this shader
	* So make sure to use it carefully.
	*
	* The result object contains the __frag__ from `shaderA` and the __vert__ from `shaderB`.
	*/
	public static function combine(shaderA:FoxShader, shaderB:FoxShader):FoxShader {
		var context = FoxRenderer.getContext();
		var gl = context.gl;

		var glProgram = gl.createProgram();
		var glShadowProgram = gl.createProgram();

		// Link shaders
		gl.attachShader(glProgram, shaderA.program.__glFragmentShader);
		gl.attachShader(glProgram, shaderB.program.__glVertexShader);
		gl.linkProgram(glProgram);

		gl.linkProgram(glShadowProgram);

		var shader = new FoxShader();
		shader.__fragSource = shaderA.__fragSource;
		shader.__vertSource = shaderB.__vertSource;
		shader.__isCombined = true;
		shader.program = context.createProgram(cast 1); // 1 = Context3DProgramFormat.GLSL
		shader.shadow = shaderB.shadow; // Use vertex shadow program

		shader.program.__glProgram = glProgram;
		shader.initCache();

		return shader;
	}

	public static function sanitizeFlags(flags:Array<String>):Array<String> {
		var sanitizedFlags:Array<String> = [];
		
		function checkAndAdd(f:Any) {
			if(!Std.isOfType(f, String)) return;
			
			var flagString = StringTools.trim(f).toUpperCase();
			if(flagString.length == 0) return;
			var flagComps:Array<String> = flagString.split("="); // Check flags that have values on them
			var flag:String = StringTools.trim(flagComps[0]);
			var flagValue:String = StringTools.trim(flagComps[1] ?? "");
			if(sanitizedFlags.filter(ff -> StringTools.startsWith(ff, flag)).length == 0) { // Add if doesn't exist
				sanitizedFlags.push(flagValue != "" ? '$flag $flagValue' : flag);
			}
		}

		for(f in flags) checkAndAdd(f);
		for(f in FoxShader.GLOBAL_FLAGS) checkAndAdd(f);

		sanitizedFlags.sort((a:String, b:String) -> a < b ? -1 : 1);
		return sanitizedFlags;
	}

	/**
		Recompiles this shader using the cached `vert` and `frag` sources.

		Optionally you can provide a new shader flags array.

		__Note:__ If this shader is a combined shader (check `combine()` for details),
		a new shader will be created and `this` will be marked as not combined.
	**/
	public function recompile(?flags:Array<String>) {
		if(flags == null) flags = FoxShader.sanitizeFlags(shaderDefines);
		disposeProgram();
		uniformCache.clear();

		// Check in cache if we have a shader with these flags from the assetsKey
		// And use its programs instead
		var defHash = flags.toString();
		if(!StringTools.startsWith(defHash, '[')) defHash = '[$defHash]';

		var cache = FoxCache.shaders().get(assetsKey + defHash);
		if(cache != null) {
			program = cache.program;
			shadow.program = cache.shadow?.program;
			__isCombined = true;
			
			initCache();
			__needsCompiling = false;
			shadow.__needsCompiling = false;
			FoxCache.shaders().set(assetsKey + defHash, this);
		}
		else {
			FoxShader.fromSources(__vertSource, __fragSource, flags, this);
			__isCombined = false;
		}
	}

	public inline function getVertexShaderLog():String {
		return gl.getShaderInfoLog(program.__glVertexShader);
	}

	public inline function getFragmentShaderLog():String {
		return gl.getShaderInfoLog(program.__glFragmentShader);
	}
	
	/*
	* Setting values:
	* The function will switch the program in order to access its uniforms and state
	* It won't recover the state, that's up to the material to handle
	* These functions are intended to be used outside any drawing pipeline
	*/

	public function setFloat(name:String, value:Float):Void {
		var data = uniformCache.get(name);
		if(data != null) {
			FoxRenderer.useShader(this);
			gl.uniform1f(cast data.location, value);
		}
	}

	public function setInt(name:String, value:Int):Void {
		var data = uniformCache.get(name);
		if(data != null) {
			FoxRenderer.useShader(this);
			gl.uniform1i(cast data.location, value);
		}
	}

	public inline function setBool(name:String, value:Bool):Void {
		setInt(name, value ? 1 : 0);
	}

	public function setSampler2D(name:String, value:FoxTexture):Void {
		if(value == null) textureInput.remove(name);
		// There's no direct input to the shader, so this will be read when rendering
		var data = uniformCache.get(name);
		if(data == null) return;
		if(textureInput.exists(name)) textureInput.get(name).value = value;
		else textureInput.set(name, {
			location: data.location,
			value: value
		});
	}

	// Inputs: float, vec2, vec3, vec4, mat2, mat3, mat4 and uniform arrays
	public function setFloatArray(name:String, values:Array<Float>):Void {
		var data = uniformCache.get(name);
		if(data == null) return;
		FoxRenderer.useShader(this);
		
		if(data.size == 1) {
			switch(data.type) {
				case UType.FLOAT: gl.uniform1f(cast data.location, values[0]); // Use setFloat() for this
				case UType.FLOAT_VEC2: gl.uniform2f(cast data.location, values[0], values[1]);
				case UType.FLOAT_VEC3: gl.uniform3f(cast data.location, values[0], values[1], values[2]);
				case UType.FLOAT_VEC4: gl.uniform4f(cast data.location, values[0], values[1], values[2], values[3]);
				#if !foxlite_polymod
				case UType.FLOAT_MAT2: gl.uniformMatrix2fv(cast data.location, false, Float32BufferCache.get(values));
				case UType.FLOAT_MAT3: gl.uniformMatrix3fv(cast data.location, false, Float32BufferCache.get(values));
				case UType.FLOAT_MAT4: gl.uniformMatrix4fv(cast data.location, false, Float32BufferCache.get(values));
				#else
				// For polymod we have to use lime GL functions, DataPointer must be working
				#if lime_webgl
				case UType.FLOAT_MAT2: GL.uniformMatrix2fvWEBGL(data.location, false, Float32BufferCache.get(values));
				case UType.FLOAT_MAT3: GL.uniformMatrix3fvWEBGL(data.location, false, Float32BufferCache.get(values));
				case UType.FLOAT_MAT4: GL.uniformMatrix4fvWEBGL(data.location, false, Float32BufferCache.get(values));
				#else
				case UType.FLOAT_MAT2: GL.uniformMatrix2fv(data.location, data.size, false, DataPointer.fromArrayBufferView(Float32BufferCache.get(values)));
				case UType.FLOAT_MAT3: GL.uniformMatrix3fv(data.location, data.size, false, DataPointer.fromArrayBufferView(Float32BufferCache.get(values)));
				case UType.FLOAT_MAT4: GL.uniformMatrix4fv(data.location, data.size, false, DataPointer.fromArrayBufferView(Float32BufferCache.get(values)));
				#end
				#end
			}
		}
		else {
			var buffer = Float32BufferCache.get(values);
			switch(data.type) {
				#if !foxlite_polymod
				case UType.FLOAT: 	   gl.uniform1fv(cast data.location, buffer);
				case UType.FLOAT_VEC2: gl.uniform2fv(cast data.location, buffer);
				case UType.FLOAT_VEC3: gl.uniform3fv(cast data.location, buffer);
				case UType.FLOAT_VEC4: gl.uniform4fv(cast data.location, buffer);
				case UType.FLOAT_MAT2: gl.uniformMatrix2fv(cast data.location, false, buffer);
				case UType.FLOAT_MAT3: gl.uniformMatrix3fv(cast data.location, false, buffer);
				case UType.FLOAT_MAT4: gl.uniformMatrix4fv(cast data.location, false, buffer);
				#else
				#if lime_webgl 		   // Why didn't they just add conditional comp for a single function? 
				case UType.FLOAT: 	   GL.uniform1fvWEBGL(data.location, buffer);
				case UType.FLOAT_VEC2: GL.uniform2fvWEBGL(data.location, buffer);
				case UType.FLOAT_VEC3: GL.uniform3fvWEBGL(data.location, buffer);
				case UType.FLOAT_VEC4: GL.uniform4fvWEBGL(data.location, buffer);
				case UType.FLOAT_MAT2: GL.uniformMatrix2fvWEBGL(data.location, false, buffer);
				case UType.FLOAT_MAT3: GL.uniformMatrix3fvWEBGL(data.location, false, buffer);
				case UType.FLOAT_MAT4: GL.uniformMatrix4fvWEBGL(data.location, false, buffer);
				#else
				case UType.FLOAT: 	   GL.uniform1fv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.FLOAT_VEC2: GL.uniform2fv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.FLOAT_VEC3: GL.uniform3fv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.FLOAT_VEC4: GL.uniform4fv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.FLOAT_MAT2: GL.uniformMatrix2fv(data.location, data.size, false, DataPointer.fromArrayBufferView(buffer));
				case UType.FLOAT_MAT3: GL.uniformMatrix3fv(data.location, data.size, false, DataPointer.fromArrayBufferView(buffer));
				case UType.FLOAT_MAT4: GL.uniformMatrix4fv(data.location, data.size, false, DataPointer.fromArrayBufferView(buffer));
				#end
				#end
			}
		}
	}

	// Inputs: int, ivec2, ivec3, ivec4, and bvec variations too, including uniform arrays
	public function setIntArray(name:String, values:Array<Int>):Void {
		var data = uniformCache.get(name);
		if(data == null) return;
		FoxRenderer.useShader(this);

		if(data.size == 1) {
			switch(data.type) {
				case UType.INT, UType.BOOL: 		  gl.uniform1i(cast data.location, values[0]); // Use setInt() for this
				case UType.INT_VEC2, UType.BOOL_VEC2: gl.uniform2i(cast data.location, values[0], values[1]);
				case UType.INT_VEC3, UType.BOOL_VEC3: gl.uniform3i(cast data.location, values[0], values[1], values[2]);
				case UType.INT_VEC4, UType.BOOL_VEC4: gl.uniform4i(cast data.location, values[0], values[1], values[2], values[3]);
			}
		}
		else {
			var buffer = Int32BufferCache.get(values);
			switch(data.type) {
				#if !foxlite_polymod
				case UType.INT, UType.BOOL: 		  gl.uniform1iv(cast data.location, buffer);
				case UType.INT_VEC2, UType.BOOL_VEC2: gl.uniform2iv(cast data.location, buffer);
				case UType.INT_VEC3, UType.BOOL_VEC3: gl.uniform3iv(cast data.location, buffer);
				case UType.INT_VEC4, UType.BOOL_VEC4: gl.uniform4iv(cast data.location, buffer);
				#else
				#if lime_webgl
				case UType.INT, UType.BOOL: 		  GL.uniform1ivWEBGL(data.location, buffer);
				case UType.INT_VEC2, UType.BOOL_VEC2: GL.uniform2ivWEBGL(data.location, buffer);
				case UType.INT_VEC3, UType.BOOL_VEC3: GL.uniform3ivWEBGL(data.location, buffer);
				case UType.INT_VEC4, UType.BOOL_VEC4: GL.uniform4ivWEBGL(data.location, buffer);
				#else
				case UType.INT, UType.BOOL: 		  GL.uniform1iv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.INT_VEC2, UType.BOOL_VEC2: GL.uniform2iv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.INT_VEC3, UType.BOOL_VEC3: GL.uniform3iv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				case UType.INT_VEC4, UType.BOOL_VEC4: GL.uniform4iv(data.location, data.size, DataPointer.fromArrayBufferView(buffer));
				#end
				#end
			}
		}
	}

	// For: bool, bvec2, bvec3, bvec4
	public inline function setBoolArray(name:String, values:Array<Bool>):Void {
		setIntArray(name, cast values);
	}

	// Vector and Matrix variations

	public function setVector2(name:String, v:Vector2):Void {
		var location = uniformCache.get(name)?.location;
		if(location != null) {
			FoxRenderer.useShader(this);
			gl.uniform2f(cast location, v.x, v.y);
		}
	}

	public function setVector3(name:String, v:Vector3D):Void {
		var location = uniformCache.get(name)?.location;
		if(location != null) {
			FoxRenderer.useShader(this);
			gl.uniform3f(cast location, v.x, v.y, v.z);
		}
	}

	public function setVector4(name:String, v:Dynamic):Void {
		var location = uniformCache.get(name)?.location;
		if(location != null) {
			FoxRenderer.useShader(this);
			gl.uniform4f(cast location, v.x, v.y, v.z, v.w);
		}
	}
	public function setMatrix4(name:String, value:Matrix3D):Void {
		var location = uniformCache.get(name)?.location;
		if(location != null) {
			FoxRenderer.useShader(this);
			for(i in 0...16) __tmpMatrix[i] = value.rawData.__array[i];
			gl.uniformMatrix4fv(cast location, false, __tmpMatrix);
		}
	}

	public inline function setMatrix4Array_Raw(name:String, value:Float32Array) {
		var data = uniformCache.get(name);
		if(data == null) return;
		FoxRenderer.useShader(this);
		#if !foxlite_polymod
		gl.uniformMatrix4fv(cast data.location, false, value);
		#else
		#if lime_webgl
		GL.uniformMatrix4fvWEBGL(data.location, false, value);
		#else
		GL.uniformMatrix4fv(data.location, data.size, false, DataPointer.fromArrayBufferView(value));
		#end
		#end
	}

	public inline function getGLProgram() {
		return program?.__glProgram;
	}

	public inline function getGLShadowProgram() {
		return shadow?.program?.__glProgram;
	}

	public function disposeProgram() {
		if(!__isCombined) program?.dispose();
		else {
			program.__glProgram = null;
			program.__glVertexShader = null;
			program.__glFragmentShader = null;
		}
		program = null;
		shadow?.disposeProgram();
	}

	public function destroy() {
		disposeProgram();
		textureInput.clear();
		uniformCache.clear();
		if(assetsKey != null) FoxCache.shaders().remove(assetsKey + ':' + shaderDefines);
		shadow?.destroy();
	}
}