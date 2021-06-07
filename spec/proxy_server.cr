require "socket"

spawn do
  server = TCPServer.new(22222)
  loop do
    socket = server.accept
    request = socket.gets("\r\n\r\n").not_nil!
    details = request.split(" ", 3)[1].split(":")
    host = details[0]
    port = details[1].to_i

    puts "connecting to #{host} #{port}..."
    client = TCPSocket.new(host, port)
    puts "proxy connection established"

    socket << "HTTP/1.1 200 OK\r\n\r\n"

    spawn do
      begin
        raw_data = Bytes.new(2048)
        while !client.closed?
          bytes_read = client.read(raw_data)
          break if bytes_read.zero? # IO was closed
          socket.write raw_data[0, bytes_read].dup
        end
      rescue IO::Error
      ensure
        socket.close
      end
    end

    begin
      out_data = Bytes.new(2048)
      while !socket.closed?
        read = socket.read(out_data)
        break if read.zero? # IO was closed
        client.write out_data[0, read].dup
      end
    rescue IO::Error
    ensure
      client.close
    end
  end
end
