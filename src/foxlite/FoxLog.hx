package foxlite;

class FoxLog {
	public static var lastLog:String;
	public static var lastWarning:String;

	public static function log(origin:String, message:String):Void {
		lastLog = message;
		trace('[FoxLite > $origin]: $message');
	}

	public static function warning(origin:String, message:String):Void {
		lastWarning = message;
		trace('[FoxLite > $origin] WARNING: $message');
	}
}