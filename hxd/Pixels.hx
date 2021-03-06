package hxd;

enum Flags {
	ReadOnly;
	AlphaPremultiplied;
	FlipY;
}

@:forward(bytes, width, height, offset, flags, clear, dispose, toPNG, clone, toVector, sub, blit)
abstract PixelsARGB(Pixels) to Pixels {


	public inline function getPixel(x, y) {
		return Pixels.switchEndian( this.bytes.getInt32(((x + y * this.width) << 2) + this.offset) );
	}

	public inline function setPixel(x, y, v) {
		this.bytes.setInt32(((x + y * this.width) << 2) + this.offset, Pixels.switchEndian(v));
	}

	@:from public static function fromPixels(p:Pixels) : PixelsARGB {
		p.convert(ARGB);
		p.setFlip(false);
		return cast p;
	}
}

@:forward(bytes, format, width, height, offset, flags, clear, dispose, toPNG, clone, toVector, sub, blit, invalidFormat, willChange)
@:access(hxd.Pixels)
abstract PixelsFloat(Pixels) to Pixels {

	public inline function getPixelF(x, y, ?v:h3d.Vector) {
		if( v == null )
			v = new h3d.Vector();
		switch(this.format) {
			case R32F:
				var pix = ((x + y * this.width) << 2) + this.offset;
				v.set(this.bytes.getFloat(pix),0,0,0);
				return v;
			case RGBA32F:
				var pix = ((x + y * this.width) << 4) + this.offset;
				v.set(this.bytes.getFloat(pix), this.bytes.getFloat(pix+4), this.bytes.getFloat(pix+8), this.bytes.getFloat(pix+12));
				return v;
			default:
				this.invalidFormat();
				return null;
		}
	}

	public inline function setPixelF(x, y, v:h3d.Vector) {
		switch(this.format) {
			case R32F:
				var pix = ((x + y * this.width) << 2) + this.offset;
				this.bytes.setFloat(pix, v.x);
			case RGBA32F:
				var pix = ((x + y * this.width) << 4) + this.offset;
				this.bytes.setFloat(pix, v.x);
				this.bytes.setFloat(pix + 4, v.y);
				this.bytes.setFloat(pix + 8, v.z);
				this.bytes.setFloat(pix + 12, v.w);
			default:
				this.invalidFormat();
		}
	}

	@:from public static function fromPixels(p:Pixels) : PixelsFloat {
		p.setFlip(false);
		return cast p;
	}

	public function convert( target : PixelFormat ) {
		if( this.format == target )
			return;
		this.willChange();
		var bytes : hxd.impl.UncheckedBytes = this.bytes;
		switch( [this.format, target] ) {

		case [RGBA32F, R32F]:
			var nbytes = haxe.io.Bytes.alloc(this.height * this.width * 4);
			var out : hxd.impl.UncheckedBytes = nbytes;
			for( i in 0 ... this.width * this.height )
				nbytes.setFloat(i << 2, this.bytes.getFloat(i << 4));
			this.bytes = nbytes;

		default:
			throw "Cannot convert from " + this.format + " to " + target;
		}

		this.innerFormat = target;
	}
}

@:enum abstract Channel(Int) {
	public var R = 0;
	public var G = 1;
	public var B = 2;
	public var A = 3;
	public inline function toInt() return this;
	public static inline function fromInt( v : Int ) : Channel return cast v;
}

@:noDebug
class Pixels {
	public var bytes : haxe.io.Bytes;
	public var format(get,never) : PixelFormat;
	public var width(default,null) : Int;
	public var height(default,null) : Int;
	public var stride(default,null) : Int;
	public var offset : Int;
	public var flags: haxe.EnumFlags<Flags>;
	var bytesPerPixel : Int;
	var innerFormat(default, set) : PixelFormat;

	public function new(width : Int, height : Int, bytes : haxe.io.Bytes, format : hxd.PixelFormat, offset = 0) {
		this.width = width;
		this.height = height;
		this.bytes = bytes;
		this.innerFormat = format;
		this.offset = offset;
		flags = haxe.EnumFlags.ofInt(0);
	}

	public static inline function switchEndian(v) {
		return (v >>> 24) | ((v >> 8) & 0xFF00) | ((v << 8) & 0xFF0000) | (v << 24);
	}

	public static inline function switchBR(v) {
		return (v & 0xFF00FF00) | ((v << 16) & 0xFF0000) | ((v >> 16) & 0xFF);
	}

	inline function get_format() return innerFormat;

	function set_innerFormat(fmt) {
		this.innerFormat = fmt;
		stride = calcStride(width,fmt);
		bytesPerPixel = calcStride(1,fmt);
		return fmt;
	}

	function invalidFormat() {
		throw "Unsupported format for this operation : " + format;
	}

	public function sub( x : Int, y : Int, width : Int, height : Int ) {
		if( x < 0 || y < 0 || x + width > this.width || y + height > this.height )
			throw "Pixels.sub() outside bounds";
		var out = haxe.io.Bytes.alloc(height * stride);
		var stride = calcStride(width, format);
		var outP = 0;
		for( dy in 0...height ) {
			var p = (x + yflip(y + dy) * this.width) * bytesPerPixel + offset;
			out.blit(outP, this.bytes, p, stride);
			outP += stride;
		}
		return new hxd.Pixels(width, height, out, format);
	}

	inline function yflip(y:Int) {
		return if( flags.has(FlipY) ) this.height - 1 - y else y;
	}

	public function blit( x : Int, y : Int, src : hxd.Pixels, srcX : Int, srcY : Int, width : Int, height : Int ) {
		if( x < 0 || y < 0 || x + width > this.width || y + height > this.height )
			throw "Pixels.blit() outside bounds";
		if( srcX < 0 || srcX < 0 || srcX + width > src.width || srcY + height > src.height )
			throw "Pixels.blit() outside src bounds";
		willChange();
		src.convert(format);
		var bpp = bytesPerPixel;
		if( bpp == 0 )
			throw "assert";
		var stride = calcStride(width, format);
		for( dy in 0...height ) {
			var srcP = (srcX + src.yflip(dy + srcY) * src.width) * bpp + src.offset;
			var dstP = (x + yflip(dy + y) * this.width) * bpp + offset;
			bytes.blit(dstP, src.bytes, srcP, stride);
		}
	}

	public function clear( color : Int, preserveMask = 0 ) {
		var mask = preserveMask;
		willChange();
		if( (color&0xFF) == ((color>>8)&0xFF) && (color & 0xFFFF) == (color >>> 16) && mask == 0 ) {
			bytes.fill(offset, width * height * bytesPerPixel, color&0xFF);
			return;
		}
		switch( format ) {
		case BGRA:
		case RGBA:
			color = switchBR(color);
			mask = switchBR(mask);
		case ARGB:
			color = switchEndian(color);
			mask = switchEndian(mask);
		default:
			invalidFormat();
		}
		var p = offset;
		if( mask == 0 ) {
			#if hl
			var bytes = @:privateAccess bytes.b;
			for( i in 0...width * height ) {
				bytes.setI32(p, color);
				p += 4;
			}
			#else
			for( i in 0...width * height ) {
				bytes.setInt32(p, color);
				p += 4;
			}
			#end
		} else {
			#if hl
			var bytes = @:privateAccess bytes.b;
			for( i in 0...width * height ) {
				bytes.setI32(p, color | (bytes.getI32(p) & mask));
				p += 4;
			}
			#else
			for( i in 0...width * height ) {
				bytes.setInt32(p, color | (bytes.getInt32(p) & mask));
				p += 4;
			}
			#end
		}
	}

	public function toVector() : haxe.ds.Vector<Int> {
		var vec = new haxe.ds.Vector<Int>(width * height);
		var idx = 0;
		var p = offset;
		var dl = 0;
		if( flags.has(FlipY) ) {
			p += ((height - 1) * width) * bytesPerPixel;
			dl = -width * 2 * bytesPerPixel;
		}
		switch(format) {
		case BGRA:
			for( y in 0...height ) {
				for( x in 0...width ) {
					vec[idx++] = bytes.getInt32(p);
					p += 4;
				}
				p += dl;
			}
		case RGBA:
			for( y in 0...height ) {
				for( x in 0...width ) {
					var v = bytes.getInt32(p);
					vec[idx++] = switchBR(v);
					p += 4;
				}
				p += dl;
			}
		case ARGB:
			for( y in 0...height ) {
				for( x in 0...width ) {
					var v = bytes.getInt32(p);
					vec[idx++] = switchEndian(v);
					p += 4;
				}
				p += dl;
			}
		default:
			invalidFormat();
		}
		return vec;
	}

	public function makeSquare( ?copy : Bool ) {
		var w = width, h = height;
		var tw = w == 0 ? 0 : 1, th = h == 0 ? 0 : 1;
		while( tw < w ) tw <<= 1;
		while( th < h ) th <<= 1;
		if( w == tw && h == th ) return this;
		var bpp = bytesPerPixel;
		var out = haxe.io.Bytes.alloc(tw * th * bpp);
		var p = 0, b = offset;
		for( y in 0...h ) {
			out.blit(p, bytes, b, w * bpp);
			p += w * bpp;
			b += w * bpp;
			for( i in 0...((tw - w) * bpp) >> 2 ) {
				out.setInt32(p, 0);
				p += 4;
			}
		}
		for( i in 0...((th - h) * tw * bpp) >> 2 ) {
			out.setInt32(p, 0);
			p += 4;
		}
		if( copy )
			return new Pixels(tw, th, out, format);
		bytes = out;
		width = tw;
		height = th;
		return this;
	}

	function copyInner() {
		var old = bytes;
		bytes = haxe.io.Bytes.alloc(height * stride);
		bytes.blit(0, old, offset, height * stride);
		offset = 0;
		flags.unset(ReadOnly);
	}

	inline function willChange() {
		if( flags.has(ReadOnly) ) copyInner();
	}

	public function setFlip( b : Bool ) {
		#if js if( b == null ) b = false; #end
		if( flags.has(FlipY) == b ) return;
		willChange();
		if( b ) flags.set(FlipY) else flags.unset(FlipY);
		if( stride%4 != 0 ) invalidFormat();
		for( y in 0...height >> 1 ) {
			var p1 = y * stride + offset;
			var p2 = (height - 1 - y) * stride + offset;
			for( x in 0...stride>>2 ) {
				var a = bytes.getInt32(p1);
				var b = bytes.getInt32(p2);
				bytes.setInt32(p1, b);
				bytes.setInt32(p2, a);
				p1 += 4;
				p2 += 4;
			}
		}
	}

	public function convert( target : PixelFormat ) {
		if( format == target )
			return;
		willChange();
		var bytes : hxd.impl.UncheckedBytes = bytes;
		switch( [format, target] ) {
		case [BGRA, ARGB], [ARGB, BGRA]:
			// reverse bytes
			for( i in 0...width*height ) {
				var p = (i << 2) + offset;
				var a = bytes[p];
				var r = bytes[p+1];
				var g = bytes[p+2];
				var b = bytes[p+3];
				bytes[p++] = b;
				bytes[p++] = g;
				bytes[p++] = r;
				bytes[p] = a;
			}
		case [BGRA, RGBA], [RGBA,BGRA]:
			for( i in 0...width*height ) {
				var p = (i << 2) + offset;
				var b = bytes[p];
				var r = bytes[p+2];
				bytes[p] = r;
				bytes[p+2] = b;
			}

		case [ARGB, RGBA]:
			for ( i in 0...width * height ) {
				var p = (i << 2) + offset;
				var a = bytes[p];
				bytes[p] = bytes[p+1];
				bytes[p+1] = bytes[p+2];
				bytes[p+2] = bytes[p+3];
				bytes[p+3] = a;
			}

		case [RGBA, ARGB]:
			for ( i in 0...width * height ) {
				var p = (i << 2) + offset;
				var a = bytes[p+3];
				bytes[p+3] = bytes[p+2];
				bytes[p+2] = bytes[p+1];
				bytes[p+1] = bytes[p];
				bytes[p] = a;
			}
		case [RGBA, R8]:
			var nbytes = haxe.io.Bytes.alloc(width * height);
			var out : hxd.impl.UncheckedBytes = nbytes;
			for( i in 0...width*height )
				out[i] = bytes[i << 2];
			this.bytes = nbytes;

		case [R32F, RGBA|BGRA]:
			var fbytes = this.bytes;
			var p = 0;
			for( i in 0...width*height ) {
				var v = Std.int(fbytes.getFloat(p)*255);
				if( v < 0 ) v = 0 else if( v > 255 ) v = 255;
				bytes[p++] = v;
				bytes[p++] = v;
				bytes[p++] = v;
				bytes[p++] = 0xFF;
			}

		case [R16U, R32F]:
			var nbytes = haxe.io.Bytes.alloc(width * height * 4);
			var fbytes = this.bytes;
			for( i in 0...width*height ) {
				var nv = fbytes.getUInt16(i << 1);
				nbytes.setFloat(i << 2, nv / 65535.0);
			}
			this.bytes = nbytes;

		case [S3TC(a),S3TC(b)] if( a == b ):
			// nothing

		#if (hl && hl_ver >= "1.10")
		case [S3TC(ver),_]:
			if( (width|height)&3 != 0 ) throw "Texture size should be 4x4 multiple";
			var out = haxe.io.Bytes.alloc(width * height * 4);
			if( !hl.Format.decodeDXT((this.bytes:hl.Bytes).offset(this.offset), out, width, height, ver) )
				throw "Failed to decode DDS";
			offset = 0;
			this.bytes = out;
			innerFormat = RGBA;
			convert(target);
			return;
		#end

		default:
			throw "Cannot convert from " + format + " to " + target;
		}

		innerFormat = target;
	}

	public function getPixel(x, y) : Int {
		var p = ((x + yflip(y) * width) * bytesPerPixel) + offset;
		switch(format) {
		case BGRA:
			return bytes.getInt32(p);
		case RGBA:
			return switchBR(bytes.getInt32(p));
		case ARGB:
			return switchEndian(bytes.getInt32(p));
		default:
			invalidFormat();
			return 0;
		}
	}

	public function setPixel(x, y, color) : Void {
		var p = ((x + yflip(y) * width) * bytesPerPixel) + offset;
		willChange();
		switch(format) {
		case R8:
			bytes.set(p, color);
		case BGRA:
			bytes.setInt32(p, color);
		case RGBA:
			bytes.setInt32(p, switchBR(color));
		case ARGB:
			bytes.setInt32(p, switchEndian(color));
		default:
			invalidFormat();
		}
	}

	public function dispose() {
		bytes = null;
	}

	public function toPNG( ?level = 9 ) {
		var png;
		setFlip(false);
		switch( format ) {
		case ARGB:
			png = std.format.png.Tools.build32ARGB(width, height, bytes #if (format >= "3.3") , level #end);
		default:
			convert(BGRA);
			png = std.format.png.Tools.build32BGRA(width, height, bytes #if (format >= "3.3") , level #end);
		}
		var o = new haxe.io.BytesOutput();
		new format.png.Writer(o).write(png);
		return o.getBytes();
	}

	public function clone() {
		var p = new Pixels(width, height, null, format);
		p.flags = flags;
		p.flags.unset(ReadOnly);
		if( bytes != null ) {
			var size = height * stride;
			p.bytes = haxe.io.Bytes.alloc(size);
			p.bytes.blit(0, bytes, offset, size);
		}
		return p;
	}

	public static function calcStride( width : Int, format : PixelFormat ) {
		return width * switch( format ) {
		case ARGB, BGRA, RGBA, SRGB, SRGB_ALPHA: 4;
		case RGBA16U, RGBA16F: 8;
		case RGBA32F: 16;
		case R8: 1;
		case R16U, R16F: 2;
		case R32F: 4;
		case RG8: 2;
		case RG16F: 4;
		case RG32F: 8;
		case RGB8: 3;
		case RGB16U, RGB16F: 6;
		case RGB32F: 12;
		case RGB10A2: 4;
		case RG11B10UF: 4;
		case S3TC(n):
			if( n == 1 || n == 4 )
				return width >> 1;
			1;
		}
	}

	static var S3TC_SIZES = [0,-1,1,1,-1,1,1,1];

	/**
		Returns the byte offset for the requested channel (0=R,1=G,2=B,3=A)
		Returns -1 if the channel is not found
	**/
	public static function getChannelOffset( format : PixelFormat, channel : Channel ) {
		return switch( format ) {
		case R8, R16F, R32F, R16U:
			if( channel == R ) 0 else -1;
		case RG8, RG16F, RG32F:
			var p = calcStride(1,format);
			[0, p, -1, -1][channel.toInt()];
		case RGB8, RGB16F, RGB32F, RGB16U:
			var p = calcStride(1,format);
			[0, p, p<<1, -1][channel.toInt()];
		case ARGB:
			[1, 2, 3, 0][channel.toInt()];
		case BGRA:
			[2, 1, 0, 3][channel.toInt()];
		case RGBA, SRGB, SRGB_ALPHA:
			channel.toInt();
		case RGBA16F, RGBA16U:
			channel.toInt() * 2;
		case RGBA32F:
			channel.toInt() * 4;
		case RGB10A2, RG11B10UF:
			throw "Bit packed format";
		case S3TC(_):
			throw "Not supported";
		}
	}

	public static function alloc( width, height, format : PixelFormat ) {
		return new Pixels(width, height, haxe.io.Bytes.alloc(height * calcStride(width, format)), format);
	}

}
