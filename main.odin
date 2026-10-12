package main

import "core:time"
import "core:bytes"
import "core:encoding/cbor"
import "core:mem"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:math"
import "core:strings"
import "core:net"
import th "core:thread"
import ma "vendor:miniaudio"

ma_device : ma.device
ma_engine: ma.engine
ip: net.IP4_Address
socket: net.UDP_Socket
PORT :: 12345
is_server: bool

input : [BUFFER_MAX]byte
input_len : u32

OUTPUT_BUFFER_MAX :: 4
BUFFER_MAX :: 20 * mem.Kilobyte
output_read_head : u32
output_write_head: u32
output : [OUTPUT_BUFFER_MAX][BUFFER_MAX]byte


is_connected : bool
endpoint : net.Endpoint

main :: proc() {
	args := os.args[1:]
	if len(args) > 1 {
		if args[1] == "server" {
			is_server = true
		}
	}
	{
		parse_ok: bool
		ip, parse_ok = net.parse_ip4_address(args[0])
		assert(parse_ok, "Invalid Address")
	}; {
		sock_err: net.Network_Error
		if is_server {
			socket, sock_err = net.make_bound_udp_socket(ip, PORT)
			assert(sock_err == nil, fmt.tprint("Socket Error", sock_err))
		} else {
			socket, sock_err = net.make_unbound_udp_socket(.IP4)
			assert(sock_err == nil, fmt.tprint("Socket Error", sock_err))
		}
	}
	net.set_option(socket, .Broadcast, true)
	defer net.close(socket)

	fmt.println(net.bound_endpoint(socket))
	fmt.println(net.peer_endpoint(socket))

	// if true do os.exit(0)

	th_send := th.create(th_send_proc)
	th_send_proc :: proc(t: ^th.Thread) {
		for {
			recv_bytes: int; recv_err: net.UDP_Recv_Error
			recv_bytes, endpoint, recv_err = net.recv(socket, output[output_write_head][:])
			output_write_head = (output_write_head+1) % OUTPUT_BUFFER_MAX
			is_connected = true
		}
	}
	th.start(th_send)


	{
		config := ma.device_config_init(.duplex)
		config.playback.format   = .f32;
		config.playback.channels = 1;
		config.capture.format    = .f32;
		config.capture.channels  = 1;
		config.sampleRate        = 48000;
		config.dataCallback      = data_callback;
		// config.pUserData         = &data;


		data_callback :: proc "c" (d: ^ma.device, o, i: rawptr, f: u32) {
			context = runtime.default_context()

			l :=	f * ma.get_bytes_per_frame(d.capture.capture_format, d.capture.channels)
			// fmt.println(f_calc)

// 			buff : [1200]u8
// 			if is_server {
// 
// 				fmt.println(net.send(socket, (cast([^]u8)i)[:l], endpoint))
// 			} else {
// 
// 			}
			bf : bytes.Buffer
			bytes.buffer_write_slice(&bf,(cast([^]f32)i)[:l])

			if is_server {
				if is_connected {
					fmt.println(net.send(socket, bytes.buffer_to_bytes(&bf), endpoint))
				}
				// recv_bytes, endpoint, recv_err = net.recv(socket, buff[:])
			} else {
				fmt.println(net.send(socket, bytes.buffer_to_bytes(&bf), { ip, PORT }))
			}
			bytes.buffer_destroy(&bf)

			if input_len != l do input_len = l
			mem.copy(&input, i, int(l))
			mem.copy(o, &output[output_read_head], int(l))
			output_read_head = (output_read_head+1) % OUTPUT_BUFFER_MAX
			// fmt.println(buff,"\n", ip)
			// fmt.println(net.last_platform_error_string())
		}

		res := ma.device_init(nil, &config, &ma_device)
		assert(res == .SUCCESS, fmt.tprint("Device Init Error:", res))

		// fmt.printf("%#v", config)
	}
	ma_device_start_res := ma.device_start(&ma_device)
	assert(ma_device_start_res == .SUCCESS, fmt.tprint("Failed to Start Device: "))

	for {
		time.sleep(1 * time.Second)
		// fmt.println(output_read_head, output_write_head)
	}
}
