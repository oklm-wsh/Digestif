module type S = Digestif_sig.S
module type T = Digestif_sig.T

module Bi         = Digestif_bigstring
module By         = Digestif_bytes
module Pp         = Digestif_pp
module Native     = Rakia_native

module type Foreign = sig
  open Native

  module Bigstring :
  sig
    val init     : ctx -> unit
    val update   : ctx -> ba -> int -> int -> unit
    val finalize : ctx -> ba -> int -> unit
  end

  module Bytes :
  sig
    val init     : ctx -> unit
    val update   : ctx -> st -> int -> int -> unit
    val finalize : ctx -> st -> int -> unit
  end

  val ctx_size   : unit -> int
end

module type Desc =
sig
  val block_size  : int
  val digest_size : int
end

module type Convenience = sig
  type t

  val compare : t -> t -> int
  val eq      : t -> t -> bool
  val neq     : t -> t -> bool
end

module Core (F : Foreign) (D : Desc) = struct
  let block_size  = D.block_size
  and digest_size = D.digest_size
  and ctx_size    = F.ctx_size ()

  module Bytes =
  struct
    type buffer = Native.st
    type ctx = Native.ctx

    include (By : Convenience with type t = Native.st)
    include Pp.Make (By) (D)

    let init () =
      let t = By.create ctx_size in
      ( F.Bytes.init t; t )

    let empty = By.create ctx_size
    let () = F.Bytes.init empty

    let unsafe_feed_bytes t buf =
      F.Bytes.update t buf 0 (By.length buf)

    let unsafe_feed_bigstring t buf =
      F.Bigstring.update t buf 0 (Bi.length buf)

    let feed_bytes t buf =
      let t = Native.dup t in
      ( unsafe_feed_bytes t buf; t )

    let feed_bigstring t buf =
      let t = Native.dup t in
      ( unsafe_feed_bigstring t buf; t )

    let feed = feed_bytes

    let feedi_bytes t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bytes t); t )

    let feedi_bigstring t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bigstring t); t )

    let feedi = feedi_bytes

    let unsafe_get t =
      let res = By.create digest_size in
      F.Bytes.finalize t res 0;
      res

    let get t = let t = Native.dup t in unsafe_get t

    let digest_bytes buf = feed_bytes empty buf |> get
    let digest_bigstring buf = feed_bigstring empty buf |> get
    let digest = digest_bytes

    let digesti_bytes iter = feedi_bytes empty iter |> get
    let digesti_bigstring iter = feedi_bigstring empty iter |> get
    let digesti = digesti_bytes

    let digestv bufs = digesti (fun f -> List.iter f bufs)
  end

  module Bigstring = struct
    type buffer = Native.ba
    type ctx = Native.ctx

    include (Bi : Convenience with type t = Native.ba)
    include Pp.Make (Bi) (D)

    let init () =
      let t = By.create ctx_size in
      ( F.Bigstring.init t; t )

    let empty = By.create ctx_size
    let () = F.Bigstring.init empty

    let unsafe_feed_bigstring t buf =
      F.Bigstring.update t buf 0 (Bi.length buf)

    let unsafe_feed_bytes t buf =
      F.Bytes.update t buf 0 (By.length buf)

    let feed_bigstring t buf =
      let t = Native.dup t in
      ( unsafe_feed_bigstring t buf; t )

    let feed_bytes t buf =
      let t = Native.dup t in
      ( unsafe_feed_bytes t buf; t )

    let feed = feed_bigstring

    let feedi_bigstring t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bigstring t); t )

    let feedi_bytes t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bytes t); t )

    let feedi = feedi_bigstring

    let unsafe_get t =
      let res = Bi.create digest_size in
      F.Bigstring.finalize t res 0;
      res

    let get t = let t = Native.dup t in unsafe_get t

    let digest_bigstring buf = feed_bigstring empty buf |> get
    let digest_bytes buf = feed_bytes empty buf |> get
    let digest = digest_bigstring

    let digesti_bigstring iter = feedi_bigstring empty iter |> get
    let digesti_bytes iter = feedi_bytes empty iter |> get
    let digesti = digesti_bigstring

    let digestv bufs = digesti (fun f -> List.iter f bufs)
  end
end

module Make (F : Foreign) (D : Desc) = struct
  type ctx = Native.ctx

  module C = Core (F) (D)

  let block_size  = C.block_size
  and digest_size = C.digest_size
  and ctx_size    = C.ctx_size

  module Bytes =
  struct
    include C.Bytes

    let opad = By.init C.block_size (fun _ -> '\x5c')
    let ipad = By.init C.block_size (fun _ -> '\x36')

    let rec norm key =
      match Pervasives.compare (By.length key) C.block_size with
      | 1  -> norm (C.Bytes.digest key)
      | -1 -> By.rpad key C.block_size '\000'
      | _  -> key

    let hmaci ~key iter =
      let key = norm key in
      let outer = Native.XOR.Bytes.xor key opad in
      let inner = Native.XOR.Bytes.xor key ipad in
      let res = C.Bytes.digesti (fun f -> f inner; iter f) in
      C.Bytes.digesti (fun f -> f outer; f res)

    let hmac ~key msg = hmaci ~key (fun f -> f msg)
    let hmacv ~key bufs = hmaci ~key (fun f -> List.iter f bufs)
  end

  module Bigstring =  struct
    include C.Bigstring

    let opad = Bi.init C.block_size (fun _ -> '\x5c')
    let ipad = Bi.init C.block_size (fun _ -> '\x36')

    let rec norm key =
      match Pervasives.compare (Bi.length key) C.block_size with
      | 1  -> norm (C.Bigstring.digest key)
      | -1 -> Bi.rpad key C.block_size '\000'
      | _  -> key

    let hmaci ~key iter =
      let key = norm key in
      let outer = Native.XOR.Bigstring.xor key opad in
      let inner = Native.XOR.Bigstring.xor key ipad in
      let res = C.Bigstring.digesti (fun f -> f inner; iter f) in
      C.Bigstring.digesti (fun f -> f outer; f res)

    let hmac ~key msg = hmaci ~key (fun f -> f msg)
    let hmacv ~key bufs = hmaci ~key (fun f -> List.iter f bufs)
  end
end

(* XXX(dinosaure): this interface provide a new function to set digest size and
   key. See #20. *)
module type ForeignBLAKE2 = sig
  open Native

  module Bigstring :
  sig
    val init      : ctx -> unit
    val update    : ctx -> ba -> int -> int -> unit
    val finalize  : ctx -> ba -> int -> unit
    val with_outlen_and_key : ctx -> int -> ba -> int -> int -> unit
  end

  module Bytes :
  sig
    val init      : ctx -> unit
    val update    : ctx -> st -> int -> int -> unit
    val finalize  : ctx -> st -> int -> unit
    val with_outlen_and_key : ctx -> int -> st -> int -> int -> unit
  end

  val ctx_size    : unit -> int
  val key_size    : unit -> int
  val digest_size : ctx -> int
end

module Make_common_BLAKE2 (F : ForeignBLAKE2) (D : Desc) : Digestif_sig.S = struct
  let block_size  = D.block_size
  and digest_size = D.digest_size (* XXX(dinosaure): short-cut [digest_size], we
                                     use [D.digest_size] when we call
                                     [F.with_outlen_and_key]. *)
  and ctx_size    = F.ctx_size ()
  and key_size    = F.key_size ()

  module Bytes =
  struct
    type buffer = Native.st
    type ctx = Native.ctx

    include (By : Convenience with type t = Native.st)
    include Pp.Make (By) (D)

    let init () =
      let t = By.create ctx_size in
      ( F.Bytes.with_outlen_and_key t digest_size By.empty 0 0; t )

    let empty = By.create ctx_size
    let () = F.Bytes.with_outlen_and_key empty digest_size By.empty 0 0

    let unsafe_feed_bytes t buf =
      F.Bytes.update t buf 0 (By.length buf)

    let unsafe_feed_bigstring t buf =
      F.Bigstring.update t buf 0 (Bi.length buf)

    let feed_bytes t buf =
      let t = Native.dup t in
      ( unsafe_feed_bytes t buf; t )

    let feed_bigstring t buf =
      let t = Native.dup t in
      ( unsafe_feed_bigstring t buf; t )

    let feed = feed_bytes

    let feedi_bytes t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bytes t); t )

    let feedi_bigstring t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bigstring t); t )

    let feedi = feedi_bytes

    let unsafe_get t =
      let res = Bytes.create digest_size in
      F.Bytes.finalize t res 0;
      res

    let get t = let t = Native.dup t in unsafe_get t

    let digest_bytes buf = feed_bytes empty buf |> get
    let digest_bigstring buf = feed_bigstring empty buf |> get
    let digest = digest_bytes

    let digesti_bytes iter = feedi_bytes empty iter |> get
    let digesti_bigstring iter = feedi_bigstring empty iter |> get
    let digesti = digesti_bytes

    let digestv bufs = digesti (fun f -> List.iter f bufs)

    let hmaci ~key iter =
      if By.length key > key_size
      then raise (Invalid_argument "BLAKE2{B,S}.hmac{v}: invalid key");

      let ctx = By.create ctx_size in
      F.Bytes.with_outlen_and_key ctx digest_size key 0 (By.length key);
      feedi ctx iter |> get

    let hmacv ~key bufs = hmaci ~key (fun f -> List.iter f bufs)
    let hmac ~key msg = hmaci ~key (fun f -> f msg)
  end

  module Bigstring =
  struct
    type buffer = Native.ba
    type ctx = Native.ctx

    include (Bi : Convenience with type t = Native.ba)
    include Pp.Make (Bi) (D)

    let init () =
      let t = By.create ctx_size in
      ( F.Bigstring.with_outlen_and_key t digest_size Bi.empty 0 0; t )

    let empty = By.create ctx_size
    let () = F.Bigstring.with_outlen_and_key empty digest_size Bi.empty 0 0

    let unsafe_feed_bytes t buf =
      F.Bytes.update t buf 0 (By.length buf)

    let unsafe_feed_bigstring t buf =
      F.Bigstring.update t buf 0 (Bi.length buf)

    let feed_bigstring t buf =
      let t = Native.dup t in
      ( unsafe_feed_bigstring t buf; t )

    let feed_bytes t buf =
      let t = Native.dup t in
      ( unsafe_feed_bytes t buf; t )

    let feed = feed_bigstring

    let feedi_bigstring t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bigstring t); t )

    let feedi_bytes t iter =
      let t = Native.dup t in
      ( iter (unsafe_feed_bytes t); t )

    let feedi = feedi_bigstring

    let unsafe_get t =
      let res = Bi.create digest_size in
      F.Bigstring.finalize t res 0;
      res

    let get t = let t = Native.dup t in unsafe_get t

    let digest_bigstring buf = feed_bigstring empty buf |> get
    let digest_bytes buf = feed_bytes empty buf |> get
    let digest = digest_bigstring

    let digesti_bigstring iter = feedi_bigstring empty iter |> get
    let digesti_bytes iter = feedi_bytes empty iter |> get
    let digesti = digesti_bigstring

    let digestv bufs = digesti (fun f -> List.iter f bufs)

    let hmaci ~key iter =
      if Bi.length key > key_size
      then raise (Invalid_argument "BLAKE2{B,S}.hmac{v}: invalid key");

      let ctx = By.create ctx_size in
      F.Bigstring.with_outlen_and_key ctx digest_size key 0 (Bi.length key);
      feedi ctx iter |> get

    let hmacv ~key bufs = hmaci ~key (fun f -> List.iter f bufs)
    let hmac ~key msg = hmaci ~key (fun f -> f msg)
  end
end

module MD5     : S = Make (Native.MD5)    (struct let (digest_size, block_size) = (16, 64) end)
module SHA1    : S = Make (Native.SHA1)   (struct let (digest_size, block_size) = (20, 64) end)
module SHA224  : S = Make (Native.SHA224) (struct let (digest_size, block_size) = (28, 64) end)
module SHA256  : S = Make (Native.SHA256) (struct let (digest_size, block_size) = (32, 64) end)
module SHA384  : S = Make (Native.SHA384) (struct let (digest_size, block_size) = (48, 128) end)
module SHA512  : S = Make (Native.SHA512) (struct let (digest_size, block_size) = (64, 128) end)
module BLAKE2B = Make_common_BLAKE2(Native.BLAKE2B) (struct let (digest_size, block_size) = (64, 128) end)
module BLAKE2S = Make_common_BLAKE2(Native.BLAKE2S) (struct let (digest_size, block_size) = (32, 64) end)
module RMD160  : S = Make (Native.RMD160) (struct let (digest_size, block_size) = (20, 64) end)

module MakeBLAKE2B (D : sig val digest_size : int end) : S =
struct
  include Make_common_BLAKE2(Native.BLAKE2B)(struct let (digest_size, block_size) = (D.digest_size, 128) end)
end

module MakeBLAKE2S (D : sig val digest_size : int end) : S =
struct
  include Make_common_BLAKE2(Native.BLAKE2S)(struct let (digest_size, block_size) = (D.digest_size, 64) end)
end

include Digestif_hash

let module_of hash =
  let b2b = Hashtbl.create 13 in
  let b2s = Hashtbl.create 13 in
  match hash with
  | Digestif_sig.MD5     -> (module MD5     : S)
  | Digestif_sig.SHA1    -> (module SHA1    : S)
  | Digestif_sig.RMD160  -> (module RMD160  : S)
  | Digestif_sig.SHA224  -> (module SHA224  : S)
  | Digestif_sig.SHA256  -> (module SHA256  : S)
  | Digestif_sig.SHA384  -> (module SHA384  : S)
  | Digestif_sig.SHA512  -> (module SHA512  : S)
  | Digestif_sig.BLAKE2B digest_size -> begin
      match Hashtbl.find b2b digest_size with
      | exception Not_found ->
        let m = (module MakeBLAKE2B(struct let digest_size = digest_size end) : S) in
        Hashtbl.replace b2b digest_size m ;
        m
      | m -> m
    end
  | Digestif_sig.BLAKE2S digest_size -> begin
      match Hashtbl.find b2s digest_size with
      | exception Not_found ->
        let m = (module MakeBLAKE2S(struct let digest_size = digest_size end) : S) in
        Hashtbl.replace b2s digest_size m ;
        m
      | m -> m
    end

module Bytes = struct
  type t = Bytes.t
  type buffer = Bytes.t

  let digest hash =
    let module H = (val (module_of hash)) in
    H.Bytes.digest

  let digestv hash =
    let module H = (val (module_of hash)) in
    H.Bytes.digestv

  let mac hash =
    let module H = (val (module_of hash)) in
    H.Bytes.hmac

  let macv hash =
    let module H = (val (module_of hash)) in
    H.Bytes.hmacv

  let of_hex hash =
    let module H = (val (module_of hash)) in
    H.Bytes.of_hex

  let to_hex hash =
    let module H = (val (module_of hash)) in
    H.Bytes.to_hex

  let pp hash =
    let module H = (val (module_of hash)) in
    H.Bytes.pp
end

module Bigstring = struct
  type t = Bi.t
  type buffer = Bi.t

  let digest hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.digest

  let digestv hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.digestv

  let mac hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.hmac

  let macv hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.hmacv

  let of_hex hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.of_hex

  let to_hex hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.to_hex

  let pp hash =
    let module H = (val (module_of hash)) in
    H.Bigstring.pp
end

let digest_size hash =
  let module H = (val (module_of hash)) in
  H.digest_size