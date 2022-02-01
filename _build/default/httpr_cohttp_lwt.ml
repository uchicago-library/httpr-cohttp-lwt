(* httpr-intf
 * httpr-curl.ml
 * test version to be promoted to httpr_ocurl package
 *)

open Prelude

let version = V.data

open Lwt
open Cohttp
open Cohttp_lwt_unix

module Result = struct
  include Result
  let map_error f = function
    | Ok o -> Ok o
    | Error e -> Error (f e)
end
   
module Syntax = struct
  let ( let+ ) x f = x >|= f
  let ( let* ) mx k = mx >>= k
end
open Syntax
 
module Redirect = struct
  let redirect resp =
    let destination =
      resp
      |> Response.headers 
      |> Header.get_location
    in
    match destination with
    | Some uri -> uri
    | None     -> assert false
end
open Redirect

module HeaderGetter : sig
  val grab_headers : Cohttp.Response.t -> string list
  val grab_content_type : Cohttp.Response.t -> string
end =
  struct
    let colonify (first, second) =
      let lowercased =
        String.map Char.lowercase_ascii first
      in
      sprintf "%s: %s" lowercased second
      
    let grab_headers_alist resp =
      let open Cohttp.Response in
      resp.headers
      |> Cohttp.Header.to_list
      
    let grab_headers =
      List.map colonify << grab_headers_alist
      
    let grab_content_type resp =
      Exn.default
        "NO CONTENT TYPE FOUND"
        (assoc "content-type")
        (grab_headers_alist resp)
  end
open HeaderGetter  

module Get = struct
  let rec unsafe_get' ?(redirects=(-1)) ?(headers=[]) uri =
    let* resp, body = Client.get ~headers:(Header.of_list headers) uri in
    let code = resp
               |> Response.status
               |> Code.code_of_status
    in
    if code / 100 = 3 && (redirects <> 0)
    then let new_redirs = if redirects < 0
                          then redirects
                          else redirects - 1
         in
         unsafe_get'
           ~redirects:new_redirs
           ~headers:headers
           (redirect resp)
    else let+ body =
           Cohttp_lwt.Body.to_string body
         in
         let reason = Code.reason_phrase_of_code code in
         let headers = grab_headers resp in
         let ctype = grab_content_type resp in
         {
           Httpr_intf.Response.uri = uri ;
           status = code ;
           reason = reason ;
           headers = headers ;
           ctype = ctype ;
           body = body ;
         }

         
  let get' ?(timeout=0) ?(verbose=false) ?(redirects=(-1)) ?(headers=[]) uri
    = let compute ~time ~f =
        Lwt.pick
          [ (f () >|= fun v -> `Done v);
            (Lwt_unix.sleep time >|= fun () -> `Timeout);
          ]
      in
      let fail_to_string = function
        | Failure str -> str
        | _ -> assert false
      in
      begin
        match timeout with
        | 0 -> unsafe_get' uri
        | _ -> let thunkd () = unsafe_get'
                                 ~redirects:(redirects)
                                 ~headers:headers
                                 uri
               in
               compute ~time:(float_of_int timeout) ~f:thunkd
               >>= function
               | `Timeout -> Lwt.fail_with
                               (sprintf
                                  "timeout expired: %i seconds"
                                  timeout)
               | `Done r -> Lwt.return r
      end
      |> Lwt_result.catch
      >|= Result.map_error (fun e -> fail_to_string e)
      
  let get uri = (Lwt_main.run << get') uri

  let gets ?(timeout=0) ?(redirects=(-1)) ?(headers=[]) lst =
    Lwt_list.map_p (get'
                      ~timeout:timeout
                      ~redirects:redirects
                      ~headers:headers) lst
    |> Lwt_main.run
end
include Get

module Post = struct

  let cleanup_headers hdrs =
    let open List in
    map
      (fun s -> (nth (String.split ~sep:":" s) 0
                , String.(trimleft whitespace)
                    (nth (String.split ~sep:":" s) 1)))
      hdrs

  let rec unsafe_post'
            ?(redirects=1)
            ?(headers=[])
            data
            uri =
    let* resp, body =
      Client.post
        ~headers:(Header.of_list @@ cleanup_headers headers)
        ~body:(Cohttp_lwt.Body.of_string data)
        uri
    in
    let code = resp
               |> Response.status
               |> Code.code_of_status
    in
    if code / 100 = 3 && (redirects <> 0)
    then let new_redirs = if redirects < 0
                          then redirects
                          else redirects - 1
         in
         unsafe_post'
           ~redirects:new_redirs
           ~headers:headers
           data
           (redirect resp)
    else let+ body =
           Cohttp_lwt.Body.to_string body
         in
         let reason = Code.reason_phrase_of_code code in
         let headers = grab_headers resp in
         let ctype = grab_content_type resp in
         {
           Httpr_intf.Response.uri = uri ;
           status = code ;
           reason = reason ;
           headers = headers ;
           ctype = ctype ;
           body = body ;
         }

  (* let post'
   *       ?(timeout=0)
   *       ?(verbose=false)
   *       ?(redirects=(-1))
   *       ?(headers=[])
   *       data
   *       uri =
   *   let compute ~time ~f =
   *       Lwt.pick
   *         [ (f () >|= fun v -> `Done v);
   *           (Lwt_unix.sleep time >|= fun () -> `Timeout);
   *         ]
   *     in
   *     let fail_to_string = function
   *       | Failure str -> str
   *       | _ -> assert false
   *     in
   *     begin
   *       match timeout with
   *       | 0 -> unsafe_post' data uri
   *       | _ -> let thunkd () = unsafe_post'
   *                                ~redirects:(redirects)
   *                                ~headers:headers
   *                                data
   *                                uri
   *              in
   *              compute ~time:(float_of_int timeout) ~f:thunkd
   *              >>= function
   *              | `Timeout -> Lwt.fail_with
   *                              (sprintf
   *                                 "timeout expired: %i seconds"
   *                                 timeout)
   *              | `Done r -> Lwt.return r
   *     end
   *     |> Lwt_result.catch
   *     >|= Result.map_error (fun e -> fail_to_string e) *)

  let post data uri = unsafe_post' data uri |> Lwt_main.run

end
include Post

  
let ssl_init () = ()



(*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *)
