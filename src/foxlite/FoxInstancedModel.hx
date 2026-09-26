package foxlite;


import flixel.util.FlxColor;
import foxlite.FoxLayer;
import foxlite.FoxModel;
import foxlite.FoxShader;
import foxlite.instancing.FoxInstanceData;
import foxlite.instancing.FoxInstanceUpdateMode;
import foxlite.math.FoxMathUtil;
import foxlite.mesh.FoxMesh;
import foxlite.renderer.FoxRenderer;
import haxe.ds.List;
import haxe.io.Bytes;
import lime.utils.Float32Array;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;

/**
	Like `FoxModel`, but designed to render a mesh multiple times, useful for particles
	or special effects.
**/
class FoxInstancedModel extends FoxModel {

	/**
		The data containing the transforms and colors information for the instances.
		This is a mat3x4 split into 3 attributes
		And an extra vec4 buffer for color/custom data
	**/
	public var instanceData:FoxInstanceData;

	/**
		The number of instances that will be rendered, this is applied per mesh.

		Increasing this value above the previous limit will rebuild `instanceData`.
	**/
	public var instanceCount(default, set):Int = 0;
	var __maxInstanceCount:Int = 0;

	/**
		Holds the pending updates for instances.
	**/
	public var __instanceUpdates:List<Int> = new List();
	
	public var __instanceMinChunk:UInt = 0xFEDE10B0;
	public var __instanceMaxChunk:Int = -1;

	public var __instanceBufferDirty:Bool = false;

	/**
		The renderer updates one instance at a time, this can cause increased API calls
		when too many instances update per frame.

		If you plan to update all instances at once, change `updateMode` to `ALL`. Keep in mind that
		this will upload the entire instance buffer even if only one needs updating.

		A balance between these modes is `CHUNK`, which uploads the region
		of the updates.
		For example: If instance 2 and 5 needs updating, the sliced
		portion of the data between those indices will be utilized (2, 3, 4, 5).
		Use this mode with caution. Tip: Update instances without any gaps in-between for best performance.
	**/
	public var updateMode:FoxInstanceUpdateMode = FoxInstanceUpdateMode.ONE_BY_ONE;

	public function new(numInstances:Int=0, x:Float=0, y:Float=0, z:Float=0, layers:FoxLayer=0x1, ?groups:Array<Int>, culling:Bool=false) {
		super(x, y, z, layers, groups, culling);
		if(numInstances > 0) {
			instanceData = new FoxInstanceData();
			instanceCount = numInstances;
		}
	}

	private function set_instanceCount(v:Int):Int {
		if(v == this.instanceCount) return v;
		// Only reallocate when we need more instances
		if(v > __maxInstanceCount) {
			if(instanceData != null) instanceData.reallocate(v);
			else FoxLog.warning('FoxInstancedModel', 'instanceData is null! Please assign one and try again!');
			__maxInstanceCount = v;
		}
		if(v == 0 || this.instanceCount == 0) {
			// Rebuild draw groups if we go from 0 -> visible and vice versa
			FoxRenderer.mustRebuildDrawGroups = true;
		}
		this.instanceCount = v;
		return v;
	}

	public override function draw(camera:FoxCamera) {
		super.draw(camera);

		switch(updateMode) {
			case FoxInstanceUpdateMode.ALL: 
				if(__instanceBufferDirty) {
					instanceData.flushAll();
					__instanceBufferDirty = false;
				};
			case FoxInstanceUpdateMode.ONE_BY_ONE: {
				for(u in __instanceUpdates) instanceData.flushInstance(u);
				__instanceUpdates.clear();
			};
			case FoxInstanceUpdateMode.CHUNK: 
				if(__instanceBufferDirty && __instanceMinChunk != 0xFEDE10B0) {
					var elements = (__instanceMaxChunk - __instanceMinChunk) * 4;
					var byteLength = elements*4;

					var bytes:Bytes = Bytes.alloc(byteLength);
					var buffer = Float32Array.fromBytes(bytes);

					var column0 = instanceData.column0;
					var column1 = instanceData.column1;
					var column2 = instanceData.column2;
					var color = instanceData.color;

					var offset = __instanceMinChunk*16;
					var i = __instanceMinChunk*16; // 4 components x 4 bytes

					bytes.blit(0, column0.bytes, i, byteLength);
					column0.glBuffer.updateFromTypedArray(buffer, offset);
					bytes.blit(0, column1.bytes, i, byteLength);
					column1.glBuffer.updateFromTypedArray(buffer, offset);
					bytes.blit(0, column2.bytes, i, byteLength);
					column2.glBuffer.updateFromTypedArray(buffer, offset);
					bytes.blit(0, color.bytes, i, byteLength);
					color.glBuffer.updateFromTypedArray(buffer, offset);
					
					FoxRenderer.allocationsThisFrame += 2;
					__instanceBufferDirty = false;
					// Reset bounds
					__instanceMaxChunk = -1;
					__instanceMinChunk = 0xFEDE10B0;
				}
		}
	}

	/**
		This function changes an instance position, rotation and scale from a matrix.

		__Note:__ This will not include the last column of the matrix.

		@param instance The instance index
		@param matrix The input matrix
	**/
	public function setInstanceTransform(instance:Int, matrix:Matrix3D) {
		instanceData.setInstanceTransform(instance, matrix);
		pushUpdate(instance);
	}

	/**
		If you want to transform an instance from a set of components, use this.
	**/
	public function setInstanceTransformSeparate(instance:Int, ?position:Vector3D, ?rotation:Vector3D, ?scale:Vector3D) {
		instanceData.setInstanceTransformSeparate(instance, position, rotation, scale);
		pushUpdate(instance);
	}

	/**
		Extracts a `Matrix3D` containing the instance transform data

		To get `position`, `rotation` and `scale`, use the matrix `decompose()`
	**/
	public function getInstanceTransform(instance:Int):Matrix3D {
		return instanceData.getInstanceTransform(instance);
	}

	/**
		Changes the color of an instance. This value gets multiplied by vertex colors
		and the `color` parameter of a material.

		@param instance The instance index
		@param color The color value in RGBA float
	**/
	public function setInstanceColor(instance:Int, color:Vector3D) {
		instanceData.setInstanceColor(instance, color);
		pushUpdate(instance);
	}

	public function setInstanceFlxColor(instance:Int, color:FlxColor) {
		instanceData.setInstanceFlxColor(instance, color);
		pushUpdate(instance);
	}

	public function getInstanceColor(instance:Int):Vector3D {
		return instanceData.getInstanceColor(instance);
	}

	public function getInstanceFlxColor(instance:Int):FlxColor {
		return instanceData.getInstanceFlxColor(instance);
	}

	public function pushUpdate(instance:Int) {
		switch(updateMode) {
			case FoxInstanceUpdateMode.ALL: __instanceBufferDirty = true;
			case FoxInstanceUpdateMode.ONE_BY_ONE: {
				__instanceUpdates.add(instance);
				FoxRenderer.allocationsThisFrame += 1;
			};
			case FoxInstanceUpdateMode.CHUNK: {
				// Naive chunk implementation, chunk can grow as big as the whole buffer
				// Implement CLUSTERS to optimize this.
				__instanceMinChunk = Std.int(Math.min(__instanceMinChunk, instance));
				__instanceMaxChunk = Std.int(Math.max(__instanceMaxChunk, instance+1));
				__instanceBufferDirty = true;
			}
		}
	}

	public override function renderMesh(mesh:FoxMesh, shader:FoxShader) {
		if(instanceCount > 0) FoxRenderer.drawMeshInstanced(context, mesh, shader, instanceCount, instanceData);
	}

	public override function isInstanced() {
		return true;
	}

	public override function pushDrawData(scene:FoxScene) {
		if(instanceCount > 0) super.pushDrawData(scene);
	}

	public override function destroy() {
		instanceData?.destroy();
		super.destroy();
	}
}