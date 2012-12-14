#!/usr/bin/env perl

use strict;
use warnings;
use GD;
use Data::Dumper;

use Steganographer;

# ----------------------------------------------------------------
# 1画素のデータ24bitうち、どのビットをデータ埋め込みに使用するかを
# $pattern に設定する。
# 画素のデータの構成は R(8bit):G(8bit):B(8bit) です。
# ----------------------------------------------------------------
# red:下位1bit blue:下位1bit を使って、
# 4ピクセルで1バイト埋め込む
my @pattern = (0x010001, 0x010001, 0x010001, 0x010001);

# red:上位1bit blue:上位1bit を使って、
# 4ピクセルで1バイト埋め込む
# (元画像は激しく劣化する。)
#my @pattern = (0x800080, 0x800080, 0x800080, 0x800080);

# red:下位3bit green:下位2bit red:下位3bit を使って
# 1ピクセルで1バイトを埋め込む
#my @pattern = (0x070307);

# red:8bit を使って
# 1ピクセルで1バイトを埋め込む
# (元画像の赤成分は完全に失われる。)
#my @pattern = (0xFF0000);

if (!valid(@pattern)) {
    die "\$pattern内に8つのbitが立つように設定してください。";
};
run();

sub run {
    if (is_decode()) {
        decode($ARGV[1]);
    } elsif (is_encode()) {
        encode($ARGV[1], $ARGV[2]);
    } else {
        usage();
    }
}

sub is_encode {
    return ((@ARGV == 3) and ($ARGV[0] eq "enc"));
}

sub is_decode {
    return ((@ARGV == 2) and ($ARGV[0] eq "dec"));
}

sub read_stdin {
    print "input string.\n";
    my @lines = <STDIN>;

    return join("", @lines);
}

sub usage {
    print STDERR "usage:\n";
    print STDERR "perl $0 enc <source_img_file> <destination_image_file>\n";
    print STDERR "perl $0 dec <img_file>\n";
}

sub encode {
    my ($src_file, $dest_file) = @_;

    my $s = Steganographer->new(\@pattern);
    $s->load($src_file);

    printf("%dバイトまで埋め込むことができます。\n", $s->{embeddable_size});

    my $string = read_stdin();
    my @data = str_to_byte_array($string);

    if (@data > $s->{embeddable_size}) {
        die "埋め込み可能なデータサイズを超えています。";
    }

    $s->encode(\@data);
    $s->save($dest_file);

    return;
}

sub decode {
    my $filename = shift;

    my $s = Steganographer->new(\@pattern);
    $s->load($filename);

    my @data = $s->decode();
    print byte_array_to_str(@data);
}

sub byte_array_to_str {
    my @data = @_;

    my $str = "";
    for (@data) {
        $str .= pack("C", $_);
    }

    return $str;
}

sub str_to_byte_array {
    my $s = shift;
    my @ret = ();

    my @bytes = split //, $s;
    for (@bytes) {
        push(@ret, unpack("C*",$_));
    }

    return @ret;
}

sub valid {
    my (@pattern) = @_;

    my $enable_bit_count = 0;
    for my $p (@pattern) {
        for (my $i = 0; $i < 24; $i++) {
            if (($p >> $i) & 1) {
                $enable_bit_count++;
            }
        }
    }
    return ($enable_bit_count == 8);
}
