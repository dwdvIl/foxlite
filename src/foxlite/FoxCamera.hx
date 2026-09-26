package foxlite;

import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import foxlite.FoxLayer;
import foxlite.animation.FoxLerp;
import foxlite.culling.BoundingBox;
import foxlite.culling.FrustumPlanes;
import foxlite.lights.FoxLightData;
import foxlite.math.FoxMathUtil;
import foxlite.renderer.FoxRenderPass;
import foxlite.renderer.FoxRenderer;
import foxlite.system.FoxDrawTree;
import foxlite.texture.FoxFramebuffer;
import foxlite.environment.FoxEnvironment;
import lime.math.Vector2;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;

class FoxCamera extends FoxObject {

	//public var position(default, set):Vector3D = new Vector3D();
	//public var rotation(default, set):Vector3D = new Vector3D();
	public var fov(default, set):Float = 90;
	public var near(default, set):Float = 0.05;
	public var far(default, set):Float = 1000.0;
	public var aspect(default, set):Float = 1;
	public var orthogonal(default, set):Bool = false;
	public var bgColor:FlxColor = 0x00000000;
	public var __aspect:Float = 1; // Target aspect
	//public var __destroyed:Bool = false;
	public var __updateProjection:Bool = true;

	/**
		Model visibility layers	
	**/
	public var modelLayers:FoxLayer = 0x1;

	/**
		 Any custom pass you want for this camera, add them here.

		 By default, there's one pass that will render everything in group 0 on the "default" render target.

		 __Warning!__ If you create two cameras, make sure to change the output or else it'll overwrite the previous camera render!
	**/
	public var passes:Array<FoxRenderPass> = [new FoxRenderPass([0], "default")];
	
	// Camera transforms
	public var viewMatrix:Matrix3D = new Matrix3D();
	public var __invViewMatrix:Matrix3D = new Matrix3D();
	public var projectionMatrix:Matrix3D = new Matrix3D();
	public var __invProjectionMatrix:Matrix3D = new Matrix3D(); // For raytracing effects

	/**
		Origin of the screen to where a perspective or isometric view would rotate
	**/
	public var projectionOrigin:FlxPoint = FlxPoint.get(0, 0);

	var __lastProjectionOrigin:FlxPoint = FlxPoint.get(0, 0);

	/**
		This is the view matrix from a previous frame, used for motion vector calculations
	**/
	public var __prevViewMatrix:Matrix3D = new Matrix3D();

	// Temporary matrix for space coordinate transforms
	public final __tempMatrix = new Matrix3D();

	
	/**
		If enabled, this camera will calculate its frustum planes and determine
		if models are inside it, culling what's outside the view and improving performance.

		This is much needed for big worlds and/or small details that are not needed
		when off-screen
	**/
	public var doFrustumCulling:Bool = true;

	public var frustumPlanes:FrustumPlanes = new FrustumPlanes();

	/**
		The light data associated with this camera.

		This handles all dynamic lighting that's visible by this camera,
		including ambient light.

		Normally, this is handled by the camera itself and the lights on the scene,
		so you don't need to touch this unless you know what you're doing!
	**/
	public var lightData:FoxLightData;

	/**
		If set, this camera will use a custom environment
	**/
	public var environment:FoxEnvironment;

	public function new(x:Float=0, y:Float=0, z:Float=0, _bgColor:FlxColor=0x0, ortho:Bool=false, withLightData:Bool=true) {
		super(x, y, z);
		bgColor = _bgColor;
		orthogonal = ortho;
		name = "FoxCamera";
		passes[0].useCameraColor = true;
		if(withLightData) lightData = new FoxLightData();
	}

	public override function update(dt:Float) {
		super.update(dt);
		if(scene == null) return;
		// Create from transform so other influences can affect the camera
		if(FoxRenderer.calculateMotionVectors) __prevViewMatrix.copyRawDataFrom(viewMatrix.rawData);
		FoxMathUtil.viewMatrixFromTransform(viewMatrix, transform);

		var updateOffset = !projectionOrigin.equals(__lastProjectionOrigin);
		if(__updateProjection || updateOffset) {
			__aspect = scene != null ? scene.__width / scene.__height : 1;
			__aspect *= aspect;
			
			if(!orthogonal) {
				FoxMathUtil.perspectiveMatrix(projectionMatrix, fov, __aspect, near, far);
			}
			else {
				FoxMathUtil.orthogonalMatrix(projectionMatrix, fov, __aspect, near, far);
			}

			if(!projectionOrigin.isZero()) {
				// shift like blender does
				var sx = projectionOrigin.x;
				var sy = projectionOrigin.y;

				if(__aspect >= 1) sy *= __aspect;
				else sx /= __aspect;
				
				if(!orthogonal) {
					projectionMatrix.rawData.__array[8] = sx * 2;
					projectionMatrix.rawData.__array[9] = sy * 2;
				}
				else {
					projectionMatrix.rawData.__array[12] = sx * 2;
					projectionMatrix.rawData.__array[13] = sy * 2;
				}
			}
			if (updateOffset)
				__lastProjectionOrigin.copyFrom(projectionOrigin);

			if(doFrustumCulling) frustumPlanes.fromProjection(projectionMatrix);

			__updateProjection = false;
		}

		// Always update view matrices, this takes a bit more hscript operations per frame
		// But fixes lights not updating accordingly

		// Do operations in-place
		__invProjectionMatrix.copyRawDataFrom(projectionMatrix.rawData);//.copyFrom(projectionMatrix); 
		__invProjectionMatrix.invert();

		__invViewMatrix.copyRawDataFrom(viewMatrix.rawData);
		__invViewMatrix.invert();
		__invViewMatrix.transpose();
	}

	public function render(drawGroups:Array<FoxDrawTree>) {
		if(scene == null) return;
		
		// Process passes
		for(pass in passes) {
			if(!pass.enabled) continue;

			// Get render target
			var framebuffer:FoxFramebuffer = scene.renderTargets.get(pass.target);
			if(framebuffer == null) {
				FoxLog.warning('FoxCamera', 'Scene does not have target "${pass.target}"');
				continue;
			}
			if(pass.groups.length == 0) {
				//FoxLog.warning('FoxCamera', 'Pass "${pass.name}" does not have groups to draw! Consider disabling this pass!');
				continue;
			}

			// Do shadow pass for all shadow lights
			if(lightData != null) pass.passShadowLights(lightData, this, drawGroups);
			
			// Do normal render pass
			pass.pass(this, drawGroups, framebuffer);
		}
	}

	public override function destroy() {
		transform = null;
		projectionMatrix = null;
		lightData?.destroy();
		projectionOrigin?.put();
		projectionOrigin = null;
		__lastProjectionOrigin?.put();
		__lastProjectionOrigin = null;
		super.destroy();
	}

	/**
		Projects a world-space 3D point to Normalized Device Coordinate (NDC, aka Screen-Space Position).
		
		__Note:__ the center is at (0,0) instead of (0.5, 0.5). If you need flixel coordinates, use `toFlixelScreenPoint()`
		
		__Note 2:__ The values are unclamped! Make sure to clamp them if needed.
	**/
	public function getScreenPoint(point:Vector3D):Vector3D {
		__tempMatrix.copyRawDataFrom(projectionMatrix.rawData);
		__tempMatrix.prepend(viewMatrix);
		var v = __tempMatrix.transformVector(point); // projectionMatrix * viewMatrix * point
		v.project(); // proj.xyz /= proj.w -> NDC
		FoxRenderer.allocationsThisFrame += 1;
		return v;
	}

	public function toFlixelScreenPoint(point:Vector3D, screenWidth:Float, screenHeight:Float, ?output:FlxPoint):FlxPoint {
		final HW = screenWidth*.5;
		final HH = screenHeight*.5;

		if(output == null) {
			output = FlxPoint.get(0, 0);
			FoxRenderer.allocationsThisFrame += 1;
		}
		output.set(
			HW + point.x * HW,
			screenHeight - (HH + point.y * HH)
		);
		return output;
	}

	/**
		Shortcut method, calls `getScreenPoint()` and then `toFlixelScreenPoint()`

		Also returns a `FlxPoint instead`
	**/
	public inline function getFlixelScreenPoint(position:Vector3D, screenWidth:Float, screenHeight:Float):FlxPoint {
		return toFlixelScreenPoint(getScreenPoint(position), screenWidth, screenHeight);
	}

	/**
		Re-projects a screen-space point to world space, useful for point and click in 3D with raycast.
	**/
	public function getWorldSpace(point:Vector3D):Vector3D {
		__tempMatrix.copyRawDataFrom(__invProjectionMatrix.rawData);
		__tempMatrix.append(__invViewMatrix);
		var v = __tempMatrix.transformVector(point);
		FoxRenderer.allocationsThisFrame += 1;
		return v;
	}

	public function loadPassesFromAsset(name:String):Void {
		passes = FoxRenderPass.fromAsset(name) ?? [];
	}

	private function set_fov(v:Float) {
		this.fov = v;
		__updateProjection = true;
		return v;
	}

	private function set_aspect(v:Float) {
		this.aspect = v;
		__updateProjection = true;
		return v;
	}

	private function set_far(v:Float) {
		this.far = v;
		__updateProjection = true;
		return v;
	}

	private function set_near(v:Float) {
		this.near = v;
		__updateProjection = true;
		return v;
	}

	private function set_orthogonal(v:Bool) {
		this.orthogonal = v;
		__updateProjection = true;
		return v;
	}
}