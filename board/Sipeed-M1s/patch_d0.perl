#!/usr/bin/env perl
#    seek:
#    0 beginning of the file (use SEEK_SET)
#    1 current position (use SEEK_CUR)
#    2 end of file (use SEEK_END)

open FD, "+<$ARGV[0]";
seek FD, -32, 2;
read FD, $char, 32;
seek FD, -32, 2;

if(unpack("H*", $char) == qq(4c504657........000000000000000000000000000000000000000000000000)) {
    # I is a 32 bytes unsigned integer, < is little endian.
    print FD "LPFW" . (pack "V", (-s $ARGV[1])) . "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";
    open FD1, "<:raw", $ARGV[1];
    print FD $_ while <FD1>;
} else {
    print $ARGV[0] . " is not a valid D0 image\n"
}
