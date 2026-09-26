package foxlite.animation;

import foxlite.animation.FoxTrackType;
import foxlite.animation.data.FoxTrackData;
import flixel.tweens.FlxEase;

class FoxAnimationTrack #if !foxlite_polymod <T> #end {
	public var name #if !foxlite_polymod (default, null) #end :String;
	public var type #if !foxlite_polymod (default, null) #end :FoxTrackType;
	public var frames:Array<FoxKeyframe<T>> = [];

	public function new(trackName:String, _type:FoxTrackType):Void {
		name = trackName;
		type = _type;
	}

	public function addFrame(time:Float, value:T, easing:FoxEaseType=#if !foxlite_polymod FoxEaseType.LINEAR #else 0 #end) {
		#if foxlite_polymod
		frames.push(new FoxKeyframe(time, value, easing));
		#else
		frames.push(new FoxKeyframe<T>(time, value, easing));
		#end
	}

	public function addFrames(times:Array<Float>, values:Array<T>, ?easings:Array<FoxEaseType>) {
		if(times.length > values.length) {
			FoxLog.warning('FoxAnimationTrack', 'Times array and values array size mismatch (${times.length} != ${values.length}). No action performed.');
			return;
		}
		else if(times.length < values.length) {
			FoxLog.warning('FoxAnimationTrack', 'Times array is smaller than values array, animation will be truncated. (${times.length} < ${values.length})');
		}
		for(i=>t in times) {
			addFrame(t, values[i], easings != null ? (easings[i] ?? FoxEaseType.LINEAR) : FoxEaseType.LINEAR);
		}
	}

	public function removeFrame(frame:FoxKeyframe<T>) {
		frames.remove(frame);
	}

	public function removeFrameByIndex(index:Int) {
		frames.splice(index, 1);
	}

	/**
	* @param closestFrame The index will be rounded towards the closest value (i.e: 0.55 between 0 and 1, the closest is 1)
	*  				if false: it will return the index of the current frame
	* @param ceil The index of the next frame will always be returned
	*/
	public function getFrameIndexByTime(time:Float, closestFrame:Bool=false, ceil:Bool=false):Int {
		for(f in 0...frames.length) {
			if(frames[f].time < time) continue;
			var index:Int = cast Math.max(f - 1, 0);
			if(ceil) return f;
			return closestFrame && (time - frames[index].time > frames[f].time - time) ? f : index;
		}
		return -1;
	}

	/**
	* @param closestFrame The index will be rounded towards the closest value (i.e: 0.55 between 0 and 1, the closest is 1)
	*  				if false: it will return the current frame
	* @param nextFrame The next frame will always be returned
	*/
	public function getFrameByTime(time:Float, closestFrame:Bool=false, nextFrame:Bool=false):FoxKeyframe<T> {
		for(f in 0...frames.length) {
			if(frames[f].time < time) continue;
			var index:Int = cast Math.max(f - 1, 0);
			if(nextFrame) return frames[f];
			return frames[closestFrame && (time - frames[index].time > frames[f].time - time) ? f : index];
		}
		return null;
	}

	public function createData():FoxTrackData {
		return new FoxTrackData(type);
	}

	public static function getEaseWeight(weight:Float, easeType:FoxEaseType):Float {
		return switch(easeType) {
			case FoxEaseType.ZERO: 	  	 0;
			case FoxEaseType.QUAD_IN: 	  	 FlxEase.quadIn(weight);
			case FoxEaseType.QUAD_OUT:   	 FlxEase.quadOut(weight);
			case FoxEaseType.QUAD_INOUT: 	 FlxEase.quadInOut(weight);
			case FoxEaseType.BACK_IN:		 FlxEase.backIn(weight);
			case FoxEaseType.BACK_INOUT:	 FlxEase.backInOut(weight);
			case FoxEaseType.BACK_OUT:		 FlxEase.backOut(weight);
			case FoxEaseType.BOUNCE_IN:	 FlxEase.bounceIn(weight);
			case FoxEaseType.BOUNCE_INOUT:	 FlxEase.bounceInOut(weight);
			case FoxEaseType.BOUNCE_OUT:	 FlxEase.bounceOut(weight);
			case FoxEaseType.CIRC_IN:	 	 FlxEase.circIn(weight);
			case FoxEaseType.CIRC_INOUT:	 FlxEase.circInOut(weight);
			case FoxEaseType.CIRC_OUT:		 FlxEase.circOut(weight);
			case FoxEaseType.CUBE_IN:	 	 FlxEase.cubeIn(weight);
			case FoxEaseType.CUBE_INOUT:	 FlxEase.cubeInOut(weight);
			case FoxEaseType.CUBE_OUT:		 FlxEase.cubeOut(weight);
			case FoxEaseType.ELASTIC_IN:	 FlxEase.elasticIn(weight);
			case FoxEaseType.ELASTIC_INOUT: FlxEase.elasticInOut(weight);
			case FoxEaseType.ELASTIC_OUT:   FlxEase.elasticOut(weight);
			case FoxEaseType.EXPO_IN:	 	 FlxEase.expoIn(weight);
			case FoxEaseType.EXPO_INOUT: 	 FlxEase.expoInOut(weight);
			case FoxEaseType.EXPO_OUT:   	 FlxEase.expoOut(weight);
			case FoxEaseType.QUART_IN:	 	 FlxEase.quartIn(weight);
			case FoxEaseType.QUART_INOUT: 	 FlxEase.quartInOut(weight);
			case FoxEaseType.QUART_OUT:   	 FlxEase.quartOut(weight);
			case FoxEaseType.QUINT_IN:	 	 FlxEase.quintIn(weight);
			case FoxEaseType.QUINT_INOUT: 	 FlxEase.quintInOut(weight);
			case FoxEaseType.QUINT_OUT:   	 FlxEase.quintOut(weight);
			case FoxEaseType.SINE_IN:	 	 FlxEase.sineIn(weight);
			case FoxEaseType.SINE_INOUT: 	 FlxEase.sineInOut(weight);
			case FoxEaseType.SINE_OUT:   	 FlxEase.sineOut(weight);
			#if (flixel >= "4.3.0")
			case FoxEaseType.SMOOTHSTEP_IN: 		FlxEase.smoothStepIn(weight);
			case FoxEaseType.SMOOTHSTEP_INOUT: 	FlxEase.smoothStepInOut(weight);
			case FoxEaseType.SMOOTHSTEP_OUT: 		FlxEase.smoothStepOut(weight);
			case FoxEaseType.SMOOTHERSTEP_IN: 		FlxEase.smootherStepIn(weight);
			case FoxEaseType.SMOOTHERSTEP_INOUT: 	FlxEase.smootherStepInOut(weight);
			case FoxEaseType.SMOOTHERSTEP_OUT: 	FlxEase.smootherStepOut(weight);
			#end
			default: weight;
		}
	}

	public function clearFrames() {
		frames.resize(0);
	}
}