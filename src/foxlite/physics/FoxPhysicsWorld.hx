package foxlite.physics;

#if lime_box3d
import openfl.geom.Vector3D;

import box3d.Box3D;
import box3d.Box3DTypes.B3WorldDef;
import box3d.Box3DTypes.B3WorldId;

import lime.system.CFFIPointer;

import foxlite.FoxBasic;
import foxlite.physics.util.Box3DUtil;
import flixel.FlxG;

class FoxPhysicsWorld extends FoxBasic {

	public var world(default, null):B3WorldDef;
	public var worldId(default, null):B3WorldId;

	/**
		For a consistant and performant physics simulation, a fixed rate is used
		always regardless of framerate. This is 50hz by default, but you can change
		it if you need it.

		__Note:__ Setting this value above the game framerate will cause physics updates
		to be called more than once per frame, it's better to keep this value
		under 100 ticks per second and use physics interpolation instead.
	**/
	public var updateRate:Int = 50;

	/**
		This is the time passed between each physics step, this can be used to slow down or
		speed up the simulation while updating it at the same rate.
	**/
	public var timeStep:Float = 1/50;
	
	/**
		This is the amount of physics update ocurring between frames for accurate collision
		detection, a value of 4 is decent enough, but it can be increased or decreased for a
		tradeoff between accuracy and speed.
		
		Too low of a value can cause high-speed objects to go trough other objects or cause jittering.
	**/
	public var subSteps:UInt = 4;

	/**
		A function to call alongside `world_Step`

		Used in FoxScene to call member's `physicsUpdate()`
	**/
	public var onPhysicsUpdate:(dt:Float)->Void;

	var elapsedTime:Float = 0;

	public var timeSinceLastStep:Float = 0;
	public var currentTime:Float = 0;

	/**
		Creates a new physics world for physics simulation.

		@param gravity The gravity for the world, follows foxlite's +Y coordinate for Up
		and -Z for Forward. Earth's gravity acceleration is 9.81 m/s -Y
		@param sleep If your game doesn't need sleep, you can get a performance boost by completely disabling this.
		@param continuousDetection If enabled, it will prevent fast-moving bodies from tunneling trough static physics objects.
		@param threads If set more than 1, simulation will be multithreaded, this will improve performance substantially
		but will take more memory.
	**/
	public function new(gravity:Vector3D=null, sleep:Bool=false, continuousDetection:Bool=true, threads:UInt=1) {
		super();
		if(gravity == null) gravity = new Vector3D(0, -9.81, 0);
		world = Box3D.defaultWorldDef();
		world.enableSleep = sleep;
		world.enableContinuous = continuousDetection;
		world.workerCount = 1;
		world.gravity.x = gravity.x;
		world.gravity.y = gravity.y;
		world.gravity.z = gravity.z;
		
		worldId = Box3D.createWorld(world);
		Box3D.world_SetUserData(worldId, new CFFIPointer(this)); // Gather this FoxPhysicsWorld back from Box3D
	}

	public static function staticInit() {
		var version = Box3D.getVersion();
		FoxLog.log('FoxPhysicsWorld', 'Initialized Box3D version ${version.major}.${version.minor} rev. ${version.revision}');
	}

	/**
		Steps the physics simulation.

		Internally, this has a delta counter so updates happen at a fixed rate.
		If the application update rate is lower than `updateRate`, more calls
		will happen per frame.

		@param dt The actual elapsed time for the application

		@returns The number of iteration steps needed for compensation. Can be 0, meaning
		no step is required this frame
	**/
	public function step(dt:Float):UInt {
		elapsedTime += dt;
		final rateMs:Float = 1/updateRate;
		var it:UInt = 0;
		while(elapsedTime >= rateMs) {
			elapsedTime -= rateMs;
			Box3D.world_Step(worldId, timeStep, subSteps);
			if(onPhysicsUpdate != null) onPhysicsUpdate(timeStep);
			timeSinceLastStep = currentTime; // add subticks to this aswell?
			++it;
		}
		return it;
	}

	public override function update(dt:Float) {
		super.update(dt);
		currentTime += dt;
		step(dt);
	}

	public inline function setGravity(x:Float=0, y:Float=-9.81, z:Float=0) {
		Box3D.world_SetGravity(worldId, Box3DUtil.toB3Vec3(new Vector3D(x, y, z)));
	}

	public function setGravityVector(gravity:Vector3D) {
		Box3D.world_SetGravity(worldId, Box3DUtil.toB3Vec3(gravity));
	}

	public function getGravity(?output:Vector3D):Vector3D {
		if(output == null) output = new Vector3D();
		var g = Box3D.world_GetGravity(worldId);
		output.setTo(g.x, g.y, g.z);
		return output;
	}

	public override function destroy() {
		Box3D.destroyWorld(worldId);
		super.destroy();
	}
}

#end