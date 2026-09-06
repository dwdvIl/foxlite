package foxlite.renderer;

import EReg;
import Reflect;
import StringTools;
import haxe.ds.StringMap;
import foxlite.FoxCache;
import foxlite.FoxShader;
import foxlite.instancing.FoxInstanceData;
import foxlite.lights.FoxLightData;
import foxlite.material.FoxBlendMode;
import foxlite.material.FoxMaterial;
import foxlite.math.FoxMathUtil;
import foxlite.mesh.FoxMesh;
import foxlite.polyfill.VectorFactory;
import foxlite.flixel.FlxTypedSignalImpl;
import foxlite.system.Int32BufferCache;
import foxlite.texture.FoxCubemapSide;
import foxlite.texture.FoxFramebuffer;
import foxlite.texture.FoxFramebufferCubemap;
import foxlite.texture.FoxTexture;
import foxlite.texture.FoxTextureFilter;
import foxlite.texture.FoxWrapMode;
import foxlite.polyfill.TypedArray;

import lime.graphics.opengl.GL;
import lime.utils.DataPointer;
import lime.utils.Float32Array;
import openfl.display3D.Context3D;
import openfl.display3D.Program3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D.textures.CubeTexture;
import openfl.display3D.textures.Texture;
import openfl.geom.Rectangle;
import flixel.FlxG;
#if foxlite_polymod
import lime.utils.DataPointer;
#end

// TODO: Make this a singleton so we don't use this many static vars
class FoxRenderer {

	public static final BUILD_NAME = "Beta";
	public static final VERSION = "0.1.1";

	public static var frameCount:Int = 0;
	public static var drawCalls:Int = 0;
	public static var verticesDrawn:Int = 0;
	public static var stateSwitches:Int = 0;
	public static var renderedInstances:Int = 0;
	public static var allocationsThisFrame:Int = 0;
	/**
		The GL render context name FoxLite is running on, this can be:
		- OPENGL: Windows/Linux
		- WEBGL: Browsers
		- OPENGLES: Mobile, ES devices
	**/
	public static var initialized:Bool = false;
	public static var renderContext:String = "";
	public static var glDeviceName:String = "";
	public static var __blendMode:FoxBlendMode = -1;
	public static var __depthTest:Bool = true;
	public static var __stencilTest:Bool = false;
	public static var __scissorTest:Bool = false;

	public static var __indexBuffer:Dynamic = null;

	public static var renderMode:Int = GL.TRIANGLES;

	/**
		If true, all scenes __must__ rebuild their draw groups.
		Draw groups are required for material and mesh drawing/sorting.

		This is set whenever:
		- A material changes render priority
		- A mesh assigned a new material
		- A model has been added/removed from a scene
		- A model has changed visibility
		- A model assigned/changed its meshes
		- Or an Instanced Model was set from/to 0 instances

		We can afford doing this per frame because the builder isn't that expensive, however
		it's better to keep it as static as possible in HScript for best performance.
	**/
	public static var mustRebuildDrawGroups:Bool = true;

	/**
		If enabled, motion vectors will be calculated for 3D objects.

		Motion vectors are used for all sort of neat effects such as Motion Blur and Temporal Reprojection,
		plus some additional advanced rendering

		Note that to output motion vector data you'll need a compatible shader with the respective flags enabled

		This technique might require a bit more memory since previous transfomation matrices are stored in memory for each object.
	**/
	public static var calculateMotionVectors:Bool = false;

	/**
		If greater than 0, forces the renderer to render using `GL.LINES` with the specified width
	**/
	public static var debugWireframe:Float = 0.0;
	public static var __shader:FoxShader = null;
	public static var __target:FoxFramebuffer = null;

	public static var context:Context3D = null;

	public static final onPreDraw:FlxTypedSignalImpl<()->Void> = new FlxTypedSignalImpl();
	public static final onPostDraw:FlxTypedSignalImpl<()->Void> = new FlxTypedSignalImpl();

	/**
		Missing texture placeholder.
	**/
	public static var MISSING_TEXTURE:FoxTexture = null;

	/**
		Missing material placeholder.
	**/
	public static var MISSING_MATERIAL:FoxMaterial = new FoxMaterial();

	/**
		Missing shader placeholder.
	**/
	public static var MISSING_SHADER:FoxShader = null;

	public static function staticInit() {
		if(FoxRenderer.initialized) return;
		var window = getWindow();
		var gl = getContext().gl;
		#if (flash || cairo)
		var msg = "This platform does not support hardware-accelerated graphics! FoxLite will not work!";
		window.alert(msg, "Get a GPU");
		#end

		#if foxlite_polymod
		trace(BUILD_NAME, VERSION, renderContext, frameCount, drawCalls, verticesDrawn, stateSwitches, __blendMode, 
			__depthTest, __shader, __stencilTest, renderMode, debugWireframe, mustRebuildDrawGroups, 
			renderedInstances, onPreDraw, onPostDraw, __indexBuffer, __scissorTest, glDeviceName, MISSING_TEXTURE, 
			MISSING_MATERIAL, MISSING_SHADER, initialized, __target, calculateMotionVectors
		);
		#end
		
		FoxRenderer.renderContext = '${window.context.type}'.toUpperCase();
		FoxRenderer.glDeviceName = gl.getParameter(gl.RENDERER);
		trace('[FoxLite > FoxRenderer]: lime is ${renderContext}:\n    - Shader model: ${GL.getParameter(context.gl.SHADING_LANGUAGE_VERSION)}\n    - Device: $glDeviceName');
	
		// Activate extensions
		var ext;
		ext = GL.getExtension("ARB_draw_buffers")
		??	  GL.getExtension("EXT_draw_buffers")
		?? 	  GL.getExtension("WEBGL_draw_buffers")
		?? 	  GL.getExtension("WEBGL_depth_texture"); // Allow the use of gl.DEPTH_STENCIL_ATTACHMENT

		ext = GL.getExtension("EXT_texture_filter_anisotropic")
  		??	  GL.getExtension("MOZ_EXT_texture_filter_anisotropic")
  		??	  GL.getExtension("WEBKIT_EXT_texture_filter_anisotropic");

		trace('[FoxLite > FoxRenderer]: Texture Anisotropy ${ext == null ?  "not" : "is"} supported.');

		// Initialize missing texture
		MISSING_TEXTURE = FoxTexture.create(2, 2, "rgba", "UNSIGNED_SHORT_4_4_4_4");
		MISSING_TEXTURE.filter = FoxTextureFilter.NEAREST;
		MISSING_TEXTURE.wrapMode = FoxWrapMode.REPEAT;

		// Upload some data
		context.__bindGLTexture2D(MISSING_TEXTURE.glTexture.__textureID);

		#if lime_webgl GL.texSubImage2DWEBGL #else GL.texSubImage2D #end (gl.TEXTURE_2D, 0, 0, 0, 2, 2, gl.RGBA, gl.UNSIGNED_SHORT_4_4_4_4, 
			// Uint8 takes 8 bits per element but our pixel only needs 4 bits, we use the a UInt16 array for two pairs of 4
			// For an element, from left to right, F represents this format: RGBA
			TypedArray.UInt16Array([0xF0FF, 0x000F, 0x000F, 0xF0FF])
		);

		MISSING_MATERIAL.name = "Missing material";
		MISSING_MATERIAL.textures.set("bitmap", MISSING_TEXTURE);
		
		// Super bare minimum shader
		MISSING_SHADER = FoxShader.fromSources("
		attribute vec4 foxlite_Position;
		attribute vec2 foxlite_TexCoord;

		uniform mat4 model;
		uniform mat4 view;
		uniform mat4 projection;

		varying vec2 foxlite_TexCoordv;

		void main(void) {
			foxlite_TexCoordv = foxlite_TexCoord*10.;
			gl_Position = projection * view * model * vec4(foxlite_Position.xyz, 1.0);
		}", "
		#ifdef GL_ES
		#ifdef GL_FRAGMENT_PRECISION_HIGH
		precision highp float;
		#else
		precision mediump float;
		#endif
		#endif

		uniform sampler2D bitmap;

		varying vec2 foxlite_TexCoordv;

		void main(void) {
			gl_FragColor = texture2D(bitmap, foxlite_TexCoordv);
		}
		");
		MISSING_MATERIAL.shader = MISSING_SHADER;
		FoxRenderer.initialized = true;
		
		if(!FlxG.signals.preStateSwitch.has(FoxCache.cleanup)) 
			FlxG.signals.preStateSwitch.add(FoxCache.cleanup);
	}

	/**
		Gets and updates the `Context3D` that can be used to do most OpenGL operations.
		This contains a `WebGLRenderContext`, meaning things can be limited
	**/
	public inline static function getContext() {
		#if foxlite_polymod
		context = FlxG.stage.context3D; // Good thing I used FlxG instead of Lib first, i didn't know it was blacklisted.
		#else
		context = openfl.Lib.current.stage.context3D;
		#end
		return context; 
	}

	/**
		Gets the current lime window the game is running on.
	**/
	public inline static function getWindow() {
		#if foxlite_polymod
		return FlxG.stage.window;
		#else
		return openfl.Lib.application.window;
		#end
	}

	public inline static function getGLVersion() {
		return getWindow().context.version;
	}

	/**
		Returns a Map containing the supported extensions for the OpenGL context.

		It is different than `gl.getSupportedExtensions()` since most of the time, the extension object does not exist even if it's listed as supported.
		This function returns the extensions that do exist in lime.
	**/
	public static function getSupportedExtensionsObject():Map<String, Dynamic> {
		var extMap:Map<String, Dynamic> = new StringMap();
		
		for(e in GL.getSupportedExtensions()) {
			var ext = GL.getExtension(e);
			if(ext != null) extMap.set(e, ext);
		}
		return extMap;
	}

	/**
		Initializes static classes
	**/
	public static function initLibs() {
		FoxMathUtil.staticInit();
		FoxCache.staticInit();
		FoxRenderer.staticInit();
		VectorFactory.staticInit();
		FoxLightData.staticInit();
		FoxShader.staticInit();
	}

	/*
	* Render funcs
	*/

	public static function begin() {
		onPreDraw.dispatch();
		// Static contexts are still weird in HScript (VS 0.8.4), so we still need to use the containing class.
		FoxRenderer.drawCalls = 0;
		FoxRenderer.verticesDrawn = 0;
		FoxRenderer.stateSwitches = 0;
		FoxRenderer.frameCount += 1;
		FoxRenderer.allocationsThisFrame = 0;
		FoxRenderer.renderedInstances = 0;
		FoxRenderer.__shader = null;
		FoxRenderer.__target = null;
		// Save previous index buffer (exclusively for FlxAnimate sprites)
		var gl = context.gl;
		FoxRenderer.__indexBuffer = gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING);
	}

	// Restore render pipeline state
	public static function backToFlixel() {
		onPostDraw.dispatch();
		context.setRenderToBackBuffer();
		
		// Default blending
		enableAlphaBlending(context);
		// No depth test (important!)
		context.setDepthTest(false, cast 0);
		context.setCulling(cast 3);
		// Reset stencil
		context.setStencilActions();
		context.setStencilReferenceValue(0);
		context.setScissorRectangle(null);
		context.setColorMask(true, true, true, true);

		var gl = context.gl;
		// Reset target color buffers
		GL.drawBuffers([gl.COLOR_ATTACHMENT0]);
		// Restore buffers
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, FoxRenderer.__indexBuffer);

		FoxRenderer.mustRebuildDrawGroups = false;
	}

	public static function generateMipmap(context:Context3D, texture:FoxTexture) {
		var gl = context.gl;
		var glTex = texture.glTexture;
		gl.bindTexture(glTex.__textureTarget, glTex.__textureID);
		gl.generateMipmap(glTex.__textureTarget);
	}

	/**
		Sets the target framebuffer where to render stuff to. Setting it to null unbinds the target.

		@param side If the target is a `FoxFramebufferCubemap`, you can specify which side of the cube to use
	**/
	public static function setTarget(?target:FoxFramebuffer, side:FoxCubemapSide=5) {
		var context = FoxRenderer.context;
		var gl = context.gl;
		
		FoxRenderer.__target = target;
		if(target == null) {
			gl.bindFramebuffer(gl.FRAMEBUFFER, null); // Use back buffer
			FoxRenderer.stateSwitches += 1;
			return;
		}
		
		// Keep stuff updated for openfl context
		context.__state.renderToTexture = target.glTexture;
		context.__state.renderToTextureDepthStencil = target.hasDepth;
		
		context.__flushGLFramebuffer();
		if(target.isCubemap()) {
			var cubeSide = getGLCubemapSide(side);
			var attachment:Int = target.hasDepth && target.hasStencil ? gl.DEPTH_STENCIL_ATTACHMENT : (
				target.hasDepth ? gl.DEPTH_ATTACHMENT : (target.hasStencil ? gl.STENCIL_ATTACHMENT : -1)
			);
			if(attachment != -1) gl.framebufferTexture2D(gl.FRAMEBUFFER, attachment, cubeSide, cast target.depthBuffer?.glTexture?.__textureID, 0);
			
			for(i=>colorAttachment in target.drawBuffers)
				gl.framebufferTexture2D(gl.FRAMEBUFFER, colorAttachment, cubeSide, cast target.colorBuffers[i]?.glTexture?.__textureID, 0);
		}
		GL.drawBuffers(target.drawBuffers);
		FoxRenderer.stateSwitches += 1;
	}

	public static function clearDepthStencil() {
		GL.depthMask(true);
		GL.stencilMask(0xFF);
		GL.clear(context.gl.DEPTH_BUFFER_BIT | context.gl.STENCIL_BUFFER_BIT);
	}

	public inline static function useShader(shader:FoxShader) {
		if(FoxRenderer.__shader != shader) {
			GL.useProgram(shader.program.__glProgram);
			FoxRenderer.__shader = FoxRenderer.frameCount == 0 ? null : shader; // Fix uniforms not updating before the renderer starts
		}
	}

	/**
		Binds a texture to a sampler texture unit in the current render state.

		In reality, a cut-down version of this method is used to set textures to uniforms,
		but this is here if you need it.

		@param sampler The sampler texture unit
		@param texture A FoxTexture
	**/
	public static function useTexture(sampler:Int, texture:FoxTexture) {
		var gl = context.gl;
		var glTexture = texture.glTexture;
		
		GL.activeTexture(gl.TEXTURE0 + sampler);

		if(glTexture.__textureTarget == gl.TEXTURE_2D) {
			context.__bindGLTexture2D(glTexture.__textureID);
		}
		else if(glTexture.__textureTarget == gl.TEXTURE_CUBE_MAP) {
			context.__bindGLTextureCubeMap(glTexture.__textureID);
		}
		
		context.setTextureAt(sampler, glTexture);
		context.setSamplerStateAt(sampler, cast texture.wrapMode, cast texture.filter, 
			cast texture.mipFilter);
		// __flushGLTextures() but cut-down
		glTexture.__setSamplerState(context.__state.samplerStates[sampler]);
		
	}

	public static function activeTextures(context:Context3D, textureInput:Map<String, foxlite.FoxShader.FoxShaderTextureInput>):Int {
		// Submit textures to GPU
		var sampler:Int = 0;
		for(t in textureInput) {
			var tex = t.value;
			
			// Missing texture check
			if(tex?.glTexture == null) tex = FoxRenderer.MISSING_TEXTURE;

			context.setTextureAt(sampler, tex.glTexture);
			context.setSamplerStateAt(sampler, cast tex.wrapMode, cast tex.filter, cast tex.mipFilter);
			GL.uniform1i(cast t.location, sampler);
			sampler += 1;
		}
		FoxRenderer.stateSwitches += sampler;
		return sampler;
	}

	/**
		Prepares a material for the render state.

		@return The next sampler index available for a texture, useful if you want to add more textures 
		to the render state afterwards.
	**/
	public static function useMaterial(context:Context3D, material:FoxMaterial):Int {
		var shader = material.shader ?? FoxRenderer.MISSING_SHADER;
		var gl = context.gl;
		
		FoxRenderer.useShader(shader);
	
		// Material data
		context.setCulling(cast material.culling);

		// Fun fact: OpenFL devs chose gl.depthMask() instead of gl.enable(depth)
		// this messes up transluscent blending...
		// instead of material.depthTest, use material.depthWrite
		context.setDepthTest(material.depthWrite, cast material.depthFunc);
		
		if(material.colorWrite) 
			context.setColorMask(true, true, true, true);
		else
			context.setColorMask(false, false, false, false);
	
		// Helper
		FoxRenderer.setBlendMode(context, material.blendMode);

		// Stencil test
		var stencil = material.stencil;
		var hasStencil = stencil != null;
		if(FoxRenderer.__stencilTest != hasStencil) {
			if(hasStencil) gl.enable(gl.STENCIL_TEST);
			else gl.disable(gl.STENCIL_TEST);
			FoxRenderer.__stencilTest = hasStencil;
			FoxRenderer.stateSwitches += 1;
		}

		// Uniforms
		material.pushShaderUniforms(shader);

		// Submit data to GPU
		var sampler = FoxRenderer.activeTextures(context, shader.textureInput);

		// __flushGL(): applies context state to gl 
		//context.__flushGLProgram();
		//context.__flushGLFramebuffer(); 
		
		if(hasStencil) {
			// This many casts are temporary until a more robust stencil system is implemented
			context.setStencilActions(cast stencil.triangleFace, cast stencil.compareMode, cast stencil.actionOnBothPass, cast stencil.actionOnDepthFail, cast stencil.actionOnFail);
			context.setStencilReferenceValue(stencil.value, stencil.readMask, stencil.writeMask);
			context.__flushGLStencil();
		}
		//context.__flushGLViewport();

		//context.__flushGLBlend(); handled by setBlendMode() now
		//context.__flushGLColor();
		context.__flushGLCulling(); 
		context.__flushGLDepth();
		//context.__flushGLScissor();
		//
		context.__flushGLTextures(); // This reallocates sampler states internally and activates/binds texture units

		// Actual depth test here
		if(FoxRenderer.__depthTest != material.depthTest) {
			FoxRenderer.__depthTest = material.depthTest;

			if(FoxRenderer.__depthTest) gl.enable(gl.DEPTH_TEST);
			else gl.disable(gl.DEPTH_TEST);

			FoxRenderer.stateSwitches += 1;
		}

		// Render mode
		if(debugWireframe <= 0.0) {
			FoxRenderer.renderMode = material.renderMode;
			if(material.renderMode == gl.LINES || material.renderMode == gl.LINE_STRIP) gl.lineWidth(material.lineWidth);
		}
		else {
			gl.lineWidth(debugWireframe);
			FoxRenderer.renderMode = gl.LINES;
		}

		FoxRenderer.stateSwitches += 1;
		return sampler;
	}

	public static function useMaterialForShadow(context:Context3D, material:FoxMaterial):Int {
		var shader = material.shader?.shadow ?? FoxRenderer.MISSING_SHADER.shadow;
		var gl = context.gl;
		
		FoxRenderer.useShader(shader);
	
		// Material data
		context.setCulling(cast material.shadowCulling); // Preferrably FRONT
		context.setDepthTest(true, cast 4); // always LESS
		FoxRenderer.setBlendMode(context, FoxBlendMode.NONE);

		if(material.colorWrite) 
			context.setColorMask(true, true, true, true);
		else
			context.setColorMask(false, false, false, false);
		
		// Stencil test
		var stencil = material.stencil;
		var hasStencil = stencil != null;
		if(FoxRenderer.__stencilTest != hasStencil) {
			if(hasStencil) gl.enable(gl.STENCIL_TEST);
			else gl.disable(gl.STENCIL_TEST);
			FoxRenderer.__stencilTest = hasStencil;
			FoxRenderer.stateSwitches += 1;
		}
		
		material.pushShaderUniforms(shader);

		var sampler = FoxRenderer.activeTextures(context, shader.textureInput);

		if(!FoxRenderer.__depthTest) {
			gl.enable(gl.DEPTH_TEST);
			FoxRenderer.__depthTest = true;
			FoxRenderer.stateSwitches += 1;
		}

		// Render mode
		if(debugWireframe <= 0.0) {
			FoxRenderer.renderMode = material.renderMode;
			if(material.renderMode == gl.LINES || material.renderMode == gl.LINE_STRIP) gl.lineWidth(material.lineWidth);
		}
		else {
			gl.lineWidth(debugWireframe);
			FoxRenderer.renderMode = gl.LINES;
		}

		if(hasStencil) {
			context.setStencilActions(cast stencil.triangleFace, cast stencil.compareMode, cast stencil.actionOnBothPass, cast stencil.actionOnDepthFail, cast stencil.actionOnFail);
			context.setStencilReferenceValue(stencil.value, stencil.readMask, stencil.writeMask);
			context.__flushGLStencil();
		}
		context.__flushGLCulling(); 
		context.__flushGLDepth();
		context.__flushGLTextures();

		FoxRenderer.stateSwitches += 1;
		return sampler;
	}

	/**
		Renders a mesh, simple as that! Render pipeline must be set up for this.
	**/
	public static function drawMesh(context:Context3D, mesh:FoxMesh, shader:FoxShader) {
		@:privateAccess var elements:Int = mesh.indexBuffer.__numIndices; // How many vertices we are drawing
		if(elements == 0) return;
		var gl = context.gl;
		var attrib = shader.attribIdx;

		// Attributes
		context.setVertexBufferAt(attrib.position, mesh.vertexBuffer, 0, cast 3);
		if(attrib.texCoord != -1) context.setVertexBufferAt(attrib.texCoord, mesh.uvBuffer, 0, cast 2);
		
		if(attrib.normal != -1) {
			context.setVertexBufferAt(attrib.normal, mesh.normalBuffer, 0, cast 3);		
			context.setVertexBufferAt(attrib.tangent, mesh.tangentBuffer, 0);
		}

		if(attrib.color != -1) context.setVertexBufferAt(attrib.color, mesh.colorBuffer, 0);

		// Skinning
		if(attrib.boneWeight != -1) context.setVertexBufferAt(attrib.boneWeight, mesh.boneWeights, 0);
		if(attrib.boneIndex != -1) switch(mesh.boneIndices?.__stride ?? -1) {
			case 4: FoxRenderer.vertexAtrribPtrUByte(context, attrib.boneIndex, mesh.boneIndices); // Unsigned Byte
			case 8: FoxRenderer.vertexAtrribPtrUShort(context, attrib.boneIndex, mesh.boneIndices); // Unsigned Short
			default: {
				GL.disableVertexAttribArray(attrib.boneIndex);
				context.__bindGLArrayBuffer(null);
			}
		}

		// Draw things the OpenGL way
		@:privateAccess // Shut up haxe everything is okay
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indexBuffer.__id);
		gl.drawElements(FoxRenderer.renderMode, elements, gl.UNSIGNED_SHORT, 0);
		
		FoxRenderer.drawCalls += 1;
		FoxRenderer.verticesDrawn += elements;
	}

	/**
		Draws a mesh multiple times via instancing, useful for particles.

		__Note:__ For this, you need to supply extra data for each individual transform,
		aswell as using an instancing-compatible shader.

		__Note 2:__ Instancing operations only works in OpenGL 3.0+
	**/
	public static function drawMeshInstanced(context:Context3D, mesh:FoxMesh, shader:FoxShader, count:Int, instanceData:FoxInstanceData) {
		@:privateAccess var elements:Int = mesh.indexBuffer.__numIndices; // How many vertices we are drawing
		if(elements == 0) return;
		var gl = context.gl;
		var attrib = shader.attribIdx;

		// Attributes
		context.setVertexBufferAt(attrib.position, mesh.vertexBuffer, 0, cast 3);
		if(attrib.texCoord != -1) context.setVertexBufferAt(attrib.texCoord, mesh.uvBuffer, 0, cast 2);
		
		if(attrib.normal != -1) {
			context.setVertexBufferAt(attrib.normal, mesh.normalBuffer, 0, cast 3);		
			context.setVertexBufferAt(attrib.tangent, mesh.tangentBuffer, 0);
		}

		if(attrib.color != -1) context.setVertexBufferAt(attrib.color, mesh.colorBuffer, 0);

		// Skinning
		if(attrib.boneWeight != -1) context.setVertexBufferAt(attrib.boneWeight, mesh.boneWeights, 0);
		if(attrib.boneIndex != -1) switch(mesh.boneIndices?.__stride ?? -1) {
			case 4: FoxRenderer.vertexAtrribPtrUByte(context, attrib.boneIndex, mesh.boneIndices); // Unsigned Byte
			case 8: FoxRenderer.vertexAtrribPtrUShort(context, attrib.boneIndex, mesh.boneIndices); // Unsigned Short
			default: {
				GL.disableVertexAttribArray(attrib.boneIndex);
				context.__bindGLArrayBuffer(null);
			}
		}

		// Instance data
		var ID = attrib.instanceData;
		
		if(ID.data0 != -1) {
			context.setVertexBufferAt(ID.data0, instanceData.column0.glBuffer, 0);
			GL.vertexAttribDivisor(ID.data0, 1);

			context.setVertexBufferAt(ID.data1, instanceData.column1.glBuffer, 0);
			GL.vertexAttribDivisor(ID.data1, 1);

			context.setVertexBufferAt(ID.data2, instanceData.column2.glBuffer, 0);
			GL.vertexAttribDivisor(ID.data2, 1);
		}
		
		if(ID.color != -1) {
			context.setVertexBufferAt(ID.color, instanceData.color.glBuffer, 0);
			GL.vertexAttribDivisor(ID.color, 1);
		}

		// Draw things the OpenGL way
		@:privateAccess // Shut up haxe everything is okay
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indexBuffer.__id);
		GL.drawElementsInstanced(FoxRenderer.renderMode, elements, gl.UNSIGNED_SHORT, 0, count);
		
		// Restore state, else everything will be void
		
		if(ID.data0 != -1) {
			GL.vertexAttribDivisor(ID.data0, 0);
			GL.vertexAttribDivisor(ID.data1, 0);
			GL.vertexAttribDivisor(ID.data2, 0);
		}
		if(ID.color != -1) GL.vertexAttribDivisor(ID.color, 0);

		FoxRenderer.drawCalls += 1;
		FoxRenderer.verticesDrawn += elements*count;
		FoxRenderer.renderedInstances += count;
	}
	
	/**
		Enables alpha blending without changing the color function
	**/
	public static function enableAlphaBlending(context:Context3D) {
		var gl = context.gl;
		var cachedState = context.__contextState;
		FoxRenderer.__blendMode = FoxBlendMode.MIX;
		gl.enable(gl.BLEND);
		gl.blendEquation(gl.FUNC_ADD);
		
		gl.blendFuncSeparate(context.__getGLBlend(cachedState.blendSourceRGBFactor), context.__getGLBlend(cachedState.blendDestinationAlphaFactor), gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
	}

	public static function setBlendMode(context:Context3D, blendMode:Int) {
		if(blendMode != FoxRenderer.__blendMode) {
			var gl = context.gl;

			if(blendMode == 0) gl.disable(gl.BLEND);
			else {
				gl.enable(gl.BLEND);
				
				// Functions
				switch(blendMode) {
					case FoxBlendMode.MIX: {
						gl.blendEquation(gl.FUNC_ADD);
						gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
					};
					case FoxBlendMode.ADD: {
						gl.blendEquation(gl.FUNC_ADD);
						gl.blendFunc(gl.ONE, gl.ONE);
					};
					case FoxBlendMode.SUBTRACT: {
						gl.blendEquation(gl.FUNC_REVERSE_SUBTRACT);
						gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
					};
					case FoxBlendMode.MULTIPLY: {
						gl.blendEquation(gl.FUNC_ADD);
						gl.blendFunc(gl.DST_COLOR, gl.ZERO);
					};
					case FoxBlendMode.PREMULTIPLIED_ALPHA: {
						gl.blendEquation(gl.FUNC_ADD);
						gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
					};
					default: {
						gl.blendEquation(gl.FUNC_ADD);
						gl.blendFunc(gl.ONE, gl.ZERO);
					};
				}
			}

			FoxRenderer.__blendMode = blendMode;
		}
	}

	public static function setScissorRect(rect:Rectangle) {
		var enabled = rect == null ? false : !rect.isEmpty();
		if(FoxRenderer.__scissorTest != enabled) {
			var gl = context.gl;
			if(enabled) {
				gl.enable(gl.SCISSOR_TEST);
				gl.scissor(Std.int(rect.x), Std.int(rect.y), Std.int(rect.width), Std.int(rect.height));
			}
			else gl.disable(gl.SCISSOR_TEST);
			FoxRenderer.__scissorTest = enabled;
		}
	}
	
	/** 
		A GPU texture that can be of any available format
		It can hold any sort of values, for deferred renderers and storage.
	
		For a friendly list of available formats, check MDN's [texImage2D() types](https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/texImage2D#type). 
		
		It applies for standard OpenGL aswell, with the exception of `WEBGL_`.
	**/
	public static function createTextureStorage(width:Int, height:Int, format:String="rgba", type:String="unsigned_byte"):Texture {
		var gl = context.gl;

		// Create dummy texture object
		FoxRenderer.allocationsThisFrame += 2;
		@:privateAccess var tex = new Texture(context, 2, 2, cast 1, false, 0);

		// Cleanup
		tex.dispose();
		
		// Now setup our texture
		tex.__width = width;
		tex.__height = height;

		// Create texture with our format to be bound to a framebuffer

		// Note: For gl.FLOAT formats in WebGL, OES_texture_float extensions MUST be enabled!!!
		gl.getExtension("OES_texture_float");
		gl.getExtension("OES_texture_half_float");

		var data = FoxRenderer.getTextureFormat(format);
		var type = Reflect.field(gl, type.toUpperCase());

		if(data.internalFormat == null || data.format == null || type == null) {
			trace("INVALID TEXTURE FORMAT!", data, type);
			return null;
		}

		tex.__textureID = gl.createTexture();
		context.__bindGLTexture2D(tex.__textureID);

		tex.__internalFormat = data.internalFormat;
		tex.__format = data.format;
		gl.texImage2D(gl.TEXTURE_2D, 0, tex.__internalFormat, width, height, 0, tex.__format, type, null);
		context.__bindGLTexture2D(null);

		return tex;
	}

	public static function createTextureCubemapStorage(size:Int, format:String="rgba", type:String="unsigned_byte"):CubeTexture {
		var gl = context.gl;

		FoxRenderer.allocationsThisFrame += 2;
		@:privateAccess var tex = new CubeTexture(context, 2, cast 1, false, 0);
		tex.dispose();
		
		// Now setup our texture
		tex.__width = size;
		tex.__height = size;

		gl.getExtension("OES_texture_float");
		gl.getExtension("OES_texture_half_float");

		var data = FoxRenderer.getTextureFormat(format);
		var type = Reflect.field(gl, type.toUpperCase());

		if(data.internalFormat == null || data.format == null || type == null) {
			trace("INVALID TEXTURE FORMAT!", data, type);
			return null;
		}

		tex.__textureID = gl.createTexture();
		context.__bindGLTextureCubeMap(tex.__textureID);

		tex.__internalFormat = data.internalFormat;
		tex.__format = data.format;
		
		// Set sides of the cubemap
		for(i in 0...6) {
			var side = gl.TEXTURE_CUBE_MAP_POSITIVE_X + i;
			gl.texImage2D(side, 0, tex.__internalFormat, size, size, 0, tex.__format, type, null);
		}
		
		context.__bindGLTextureCubeMap(null);
		
		return tex;
	}

	public static function getGLCubemapSide(side:FoxCubemapSide):Int {
		var gl = context.gl;
		return switch(side) {
			case FoxCubemapSide.RIGHT: gl.TEXTURE_CUBE_MAP_POSITIVE_X;
			case FoxCubemapSide.LEFT: gl.TEXTURE_CUBE_MAP_NEGATIVE_X;
			case FoxCubemapSide.TOP: gl.TEXTURE_CUBE_MAP_POSITIVE_Y;
			case FoxCubemapSide.BOTTOM: gl.TEXTURE_CUBE_MAP_NEGATIVE_Y;
			case FoxCubemapSide.BACK: gl.TEXTURE_CUBE_MAP_POSITIVE_Z;
			case FoxCubemapSide.FRONT: gl.TEXTURE_CUBE_MAP_NEGATIVE_Z;
			default: throw "Illegal operation";
		}
	}

	public static function checkFrameBuffer():Bool {
		var gl = context.gl;
		var status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
		if(status != gl.FRAMEBUFFER_COMPLETE) {
			trace('[FoxLite > FoxRenderer] Warning: FRAMEBUFFER NOT COMPLETE. Status: $status');
			return false;
		}
		return true;
	}

	public static function getTextureFormat(fmt:String):{internalFormat:Null<Int>, format:Null<Int>} {
		var gl = context.gl;
		fmt = fmt.toUpperCase();

		if(fmt == "LUMINANCE" || fmt == "ALPHA" || fmt == "LUMINANCE_ALPHA") return {
			internalFormat: Reflect.field(gl, fmt),
			format: Reflect.field(gl, fmt)
		};
		else if(StringTools.startsWith(fmt, "DEPTH_COMPONENT")) return {
			internalFormat: Reflect.field(gl, fmt),
			format: gl.DEPTH_COMPONENT
		}
		else if(StringTools.endsWith(fmt, "STENCIL8")) return {
			internalFormat: Reflect.field(gl, fmt),
			format: gl.DEPTH_STENCIL
		}

		var format = "";
		var isInt = StringTools.endsWith(fmt, "I");

		for(c in ["R","G","B","A"]) if(StringTools.contains(fmt, c)) format += c;
		if(format == "R") format = "RED"; // Single channel has this special name

		format += isInt ? "_INTEGER" : "";
		return {
			internalFormat: Reflect.field(gl, fmt),
			format: Reflect.field(gl, format)
		};
	}

	/**
	* Uploads vertex and fragment sources for the GLSL program.
	* This is a cut-down copy of `Program3D.uploadSources()` to remove that annoying prefix and reduce memory usage/processing
	*/
	public static function uploadFromGLSLProgram3D(program:Program3D, vertexSource:String, fragmentSource:String) {
		var gl = context.gl;
		program.__deleteShaders();
		try {
			program.__uploadFromGLSL(vertexSource, fragmentSource);
		}
		catch(e:String) {
			// Better shader error handler
			// Performance isn't the best, but that's not the priority here
			var err = new EReg("ERROR:\\s+(.+?):\\s+('.+)\\n", 'i');
			if(!err.match(e)) {
				// Match failed case?
				getWindow().alert(e);
			}
			else {
				var line = Std.parseInt(err.matched(1).split(':')[1]);
				var errMsg = 'Near line $line: ${err.matched(2)}';
				line -= 2;
				if(line < 0) line = 0;
				
				final errVert = StringTools.urlDecode("%5D%20ERROR%3A%20Error%20compiling%20vertex%20shader");
				final errFrag = StringTools.urlDecode("%5D%20ERROR%3A%20Error%20compiling%20fragment%20shader");

				var isVertex = StringTools.contains(e, errVert);
				var isFragment = StringTools.contains(e, errFrag);

				var source = isVertex ? vertexSource : fragmentSource;
				var lines = source.split('\n');
				var msg = 'Error compiling ${isVertex ? 'vertex':'fragment'} shader!\n$errMsg\n';

				for(i in line-5...line+5) {
					var lineMsg = '${i+2} ${lines[i]}';
					if(i == line) lineMsg = '>$lineMsg';
					msg += '\n$lineMsg';
				}
				getWindow().alert(msg);
			}
		}
	}

	public static function updateVertexBuffer(context:Context3D, buffer:VertexBuffer3D, data:Float32Array, offset:Int=0) {
		var gl = context.gl;
		offset *= 4;
		context.__bindGLArrayBuffer(buffer.__id);
		#if foxlite_polymod
		#if lime_webgl
		GL.bufferSubDataWEBGL(gl.ARRAY_BUFFER, offset, data);
		#else
		GL.bufferSubData(gl.ARRAY_BUFFER, offset, data.length*4, DataPointer.fromArrayBufferView(data));
		#end
		#else
		gl.bufferSubData(gl.ARRAY_BUFFER, offset, data);
		#end
	}

	public static function vertexAtrribPtrUByte(context:Context3D, index:Int, buffer:VertexBuffer3D, bufferOffet:Int=0) {
		if(buffer == null) {
			GL.disableVertexAttribArray(index);
			context.__bindGLArrayBuffer(null);
			return;
		}
		context.__bindGLArrayBuffer(buffer.__id);
		GL.enableVertexAttribArray(index); //  		     	       vvvvv literally just fixing this
		GL.vertexAttribPointer(index, 4, context.gl.UNSIGNED_BYTE, false, buffer.__stride, bufferOffet);
	}

	public static function vertexAtrribPtrUShort(context:Context3D, index:Int, buffer:VertexBuffer3D, bufferOffet:Int=0) {
		if(buffer == null) {
			GL.disableVertexAttribArray(index);
			context.__bindGLArrayBuffer(null);
			return;
		}
		context.__bindGLArrayBuffer(buffer.__id);
		GL.enableVertexAttribArray(index);
		GL.vertexAttribPointer(index, 4, context.gl.UNSIGNED_SHORT, false, buffer.__stride, bufferOffet);
	}
}