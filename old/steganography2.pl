#!/usr/bin/env perl

# リファクタリングしました。
# まだユーモアがないので、出直してきます！
# 何度もすみません。(>_<;
#
# 文字列埋め込み画像
# https://github.com/18hb/steganography/blob/master/embedded.png

use strict;
use warnings;
use GD;
use Data::Dumper;

run();

sub run {
    if (is_decode()) {
        decode($ARGV[1]);
    } elsif (is_encode()) {
        my $str = read_stdin();
        encode($ARGV[1], $ARGV[2], $str);
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
    my ($src_file, $dest_file, $string) = @_;

    my @data = str_to_byte_array($string);

    my $s = Steganographer->new;
    $s->load($src_file);
    $s->encode(\@data);
    $s->save($dest_file);

    return;
}

sub decode {
    my $filename = shift;

    my $s = Steganographer->new;
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

# ------------------------------------------------------------
# エンコード／デコードモジュール
# ------------------------------------------------------------
package Steganographer;

sub new {
    my ($class) = @_;

    my $data = {
        image => undef,
    };

    my $self = bless $data, $class;
    return $self;
}

sub load {
    my $self = shift;
    my $filename = shift;

    $self->{image} = GD::Image->newFromPng($filename, 1);
}

sub save {
    my $self = shift;
    my $filename = shift;

    open OUT, ">$filename" || die "Cannot open file: $filename";
    binmode OUT;
    print OUT $self->{image}->png;
    close OUT;
}

# 画像データに、文字列データを埋め込む。
# $data: 埋め込むデータのバイト配列のリファレンス
sub encode {
    my $self = shift;
    my $data = shift;

    my $len = @$data;

    # とりあえず65536バイトまで埋め込める想定
    my $len_hex = sprintf("%04X", $len);
    my @len_bytes = $self->_hex_to_byte_array($len_hex);

    # 埋め込んであるデータのサイズも画像に埋め込む。
    # 先頭2バイトをデータサイズとして使用。
    unshift(@$data, @len_bytes);

    my $i = 0;
    for (@$data) {
        $self->_embed_1byte($_, $i);
        $i++;
    }
}

# データ1バイトを画像データに埋め込む
#
# 4ピクセルを使って1バイトを埋め込む。
# 赤成分に4bit,青成分に4bitを割り振る。
# 人間の目は緑に敏感だとかというのをどこかで聞いたので、
# 緑成分は変更しないでみる。気休め程度かも。
#
# $data:  埋め込むデータ 1byte
# $index: 埋め込むデータが何バイト目なのか
sub _embed_1byte {
    my $self = shift;
    my $data = shift;
    my $index = shift;

    #printf("%02X ", $data);
    #for (0..7) {
    #    printf("%d", (($data << $_) & 0x80) > 0 ? 1 : 0);
    #}
    #print "\n";

    # 埋め込み対象画素 開始添字
    my $start = $index * 4;

    # 4ピクセル分の色データ取得
    my (@color4px) = $self->_get_rgb4($start);

    # 上位4bitを赤成分、下位4bitを青成分に埋め込む
    for (0..7) {
        my $bit = (($data << $_) & 0x80) > 0 ? 1 : 0;

        if ($_ < 4) {
            # embed into red
            $color4px[$_ % 4]->[0] = $self->_embed_1bit($color4px[$_ % 4]->[0], $bit);
        } else {
            # embed into blue
            $color4px[$_ % 4]->[2] = $self->_embed_1bit($color4px[$_ % 4]->[2], $bit);
        }
    }

    # 埋め込んだデータをGDオブジェクトへ書き込む
    my $i = $start;
    for (@color4px) {
        my $rgb = $_;
        $self->_set_rgb($i++, $rgb);
    }
}

# データ1bitを画像に埋め込む
# 色データの値(0〜255)が偶数なら0、奇数なら1とみなす。
#
# $data: 埋め込む画素の色データ
# $bit:  埋め込むデータ(0 or 1)
sub _embed_1bit {
    my $self = shift;
    my $data = shift;
    my $bit = shift;

    if ($bit) {
        return ($data | 0x01);
    } else {
        return ($data & 0xFE);
    }
}

# 左上を0番目として、$i番目から4画素分の色データを取得する
sub _get_rgb4 {
    my $self = shift;
    my $i = shift;

    my @ret = ();
    for ($i .. ($i + 3)) {
        my ($r, $g, $b) = $self->_get_rgb($_);
        push(@ret, [$r, $g, $b]);
    }

    return @ret;
}

# 左上を0番目として、$i番目の画素の色データを取得する
sub _get_rgb {
    my $self = shift;
    my $i = shift;

    my ($x, $y) = $self->_i_to_xy($i);
    my $color = $self->{image}->getPixel($x, $y);
    my ($r, $g, $b) = $self->{image}->rgb($color);

    return $r, $g, $b;
}

# 左上を0番目として、$i番目の画素に色をセットする
sub _set_rgb {
    my $self = shift;
    my $i = shift;
    my $rgb = shift;

    my $r = @$rgb[0];
    my $g = @$rgb[1];
    my $b = @$rgb[2];

    #printf("%02X, %02X, %02X\n", $r, $g, $b);

    my ($x, $y) = $self->_i_to_xy($i);

    my $color = $self->{image}->colorAllocate($r, $g, $b);
    $self->{image}->setPixel($x, $y, $color);
    $self->{image}->colorDeallocate($color);
}

# デコードする
sub decode {
    my $self = shift;

    # 埋め込んであるデータのサイズ(バイト)を取得
    my $size = $self->_get_embedded_size();

    # 4ピクセルを使って1バイトを埋め込んでいるので
    # 画像のピクセル数に収まらないデータサイズなら
    # データは埋め込まれてないないと判断する。
    my $num_of_pixel = $self->{image}->width * $self->{image}->height;
    my $max_data_size = int($num_of_pixel / 4) - 2;
    if ($size > $max_data_size) {
        die("Cannot decode.");
    }

    my @embedded_data = $self->_get_data($size);
    return @embedded_data;
}

# 埋め込まれているデータのバイト数を取得する
sub _get_embedded_size {
    my $self = shift;

    # 先頭2バイトに、埋め込んだデータのサイズ(バイト数)を書き込んである
    my $d0 = $self->_get_data_1byte(0);
    my $d1 = $self->_get_data_1byte(1);

    return (($d0 << 8) | $d1);
}

# 画像データから $size バイト分のデータを取り出す
sub _get_data {
    my $self = shift;
    my $size = shift;

    my @ret = ();

    # 先頭2バイトにはデータの長さが書き込んであるので
    # 3バイト目から取得する
    for (2 .. (2 + $size - 1)) {
        push(@ret, $self->_get_data_1byte($_));
    }

    return @ret;
}

# 画像に埋め込まれている$indexバイト目のデータを取得する
# 4ピクセルで1バイトのデータを埋め込んでいる
sub _get_data_1byte {
    my $self = shift;
    my $index = shift;

    my $start = $index * 4;

    # 4ピクセル分の色データ
    my @color4px = $self->_get_rgb4($start);

    my $data = 0;

    # 赤に上位4bit埋め込み
    $data |= (($color4px[0]->[0] & 0x01) << 7);
    $data |= (($color4px[1]->[0] & 0x01) << 6);
    $data |= (($color4px[2]->[0] & 0x01) << 5);
    $data |= (($color4px[3]->[0] & 0x01) << 4);

    # 青に下位4bit埋め込み
    $data |= (($color4px[0]->[2] & 0x01) << 3);
    $data |= (($color4px[1]->[2] & 0x01) << 2);
    $data |= (($color4px[2]->[2] & 0x01) << 1);
    $data |= (($color4px[3]->[2] & 0x01) << 0);

    return $data;
}

sub _i_to_xy {
    my $self = shift;
    my $i = shift;

    my $width = $self->{image}->width;
    my $x = $i % $width;
    my $y = int($i / $width);

    return $x, $y;
}

sub _hex_to_byte_array {
    my $self = shift;
    my $hex = shift;

    my @ret = ();
    for (my $i = 0; $i < length($hex); $i+=2) {
        push(@ret, hex(substr($hex, $i, 2)));
    }

    return @ret;
}
