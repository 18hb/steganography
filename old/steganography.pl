#!/usr/bin/perl

use strict;
use warnings;
use GD;
use Data::Dumper;

sub run {
    if ((@ARGV == 2) and ($ARGV[0] eq "dec")) {
        &dec($ARGV[1]);
    } elsif ((@ARGV == 3) and ($ARGV[0] eq "enc")) {
        print("input string.\n");
        my @lines = <STDIN>;
        &enc($ARGV[1], $ARGV[2], join("", @lines));
    } else {
        &usage;
    }
}

sub usage {
    print "\$ perl $0 enc <source_img_file> <destination_image_file>\n";
    print "\$ perl $0 dec <img_file>\n";
}

sub enc {
    my ($src_file, $dest_file, $string) = @_;

    my $img = &read_image($src_file);
    my ($r, $g, $b) = &get_rgb($img);
    my @data = &str_to_byte_array($string);

#    printf("--- red ---\n");
#    &_dump($r, $img->width);
#    printf("--- green ---\n");
#    &_dump($g, $img->width);
#    printf("--- blue ---\n");
#    &_dump($b, $img->width);

    # データを赤成分と青成分に書き込む
    # $r と $b は上書きされる
    &embed($r, $b, \@data);
#
#    printf("--- red ---\n");
#    &_dump($r, $img->width);
#    printf("--- green ---\n");
#    &_dump($g, $img->width);
#    printf("--- blue ---\n");
#    &_dump($b, $img->width);

    &save_image($img, $r, $g, $b);
    &save_file($dest_file, $img->png);
}

sub save_image {
    my ($img, $ra, $ga, $ba) = @_;

    my $w = $img->width;
    my $h = $img->height;

    for (my $y = 0; $y < $h; $y++) {
        for (my $x = 0; $x < $w;  $x++) {
            my $i = $x + $y * $w;
            my $color = $img->colorAllocate($$ra[$i], $$ga[$i], $$ba[$i]);
            $img->setPixel($x, $y, $color);
            $img->colorDeallocate($color);
        }
    }
}

sub save_file {
    my ($filename, $image_data) = @_;

    open(OUT, ">$filename") || die("Cannot open file: $filename");
    binmode OUT;
    print OUT $image_data;
    close OUT;
}

# 画像データに、文字列データを埋め込む。
# 画像データのコピーは作らずに、サブルーチン呼び出し元の画像データ配列を上書きします。
#
# $r: 赤の要素の配列のリファレンス
# $b: 青の要素の配列のリファレンス
# $data: 埋め込むデータのバイト配列のリファレンス
sub embed {
    my ($r, $b, $data) = @_;

    my $len = @$data;

    # とりあえず65536(2bytes)文字まで埋め込める想定
    my $len_hex = sprintf("%04X", $len);
    my @len_bytes = &hex_to_byte_array($len_hex);

    # 埋め込んであるデータのサイズも画像に埋め込む。
    # 先頭2バイトをデータサイズとして使用。
    unshift(@$data, @len_bytes);

    my $i = 0;
    for (@$data) {
        &embed_1byte($r, $b, $_, $i);
        $i++;
    }
}

sub hex_to_byte_array {
    my $hex = shift;

    my @ret = ();
    for (my $i = 0; $i < length($hex); $i+=2) {
        push(@ret, hex(substr($hex, $i, 2)));
    }

    return @ret;
}

# データ1バイトを画像データに埋め込む
#
# 4ピクセルを使って1バイトを埋め込む。
# 赤成分に4bit,青成分に4bitを割り振る。
# 人間の目は緑に敏感だとかというのをどこかで聞いたので、
# 緑成分は変更しないでみる。気休め程度かも。
#
# $r: 赤の要素の配列のリファレンス
# $b: 青の要素の配列のリファレンス
# $data: 埋め込むデータ 1byte
# $index: 埋め込むデータが何バイト目なのか
sub embed_1byte {
    my ($r, $b, $data, $index) = @_;

    my $bin = sprintf("%08B", $data);
    my @bin = split //, $bin;
    #printf("%2d, %02X %s\n", $index, $data, $bin);

    # 埋め込み対象画素 開始添字
    my $start = $index * 4;

    my $i = 0;
    for (@bin) {
        # 最初の4bitを赤に、後ろ4bitを青に割り振る
        my $target = ($i < 4 ? $r : $b);
        &embed_1bit($target, $start + ($i % 4), $_);
        $i++;
    }
}

# データ1bitを画像に埋め込む
# 色データの値(0〜255)が偶数なら0、奇数なら1とみなす。
sub embed_1bit {
    my ($color_array, $i, $data) = @_;
    my $color = $$color_array[$i];

    if (($color % 2) != $data) {
        if ($color + 1 > 255) {
            $color--;
        } else {
            $color++;
        }
        $$color_array[$i] = $color;
    }
}

sub get_rgb {
    my $img = shift;

    my $width = $img->width;
    my $height = $img->height;

    my @red = ();
    my @green = ();
    my @blue = ();

    for (my $y = 0; $y < $height; $y++) {
        for (my $x = 0; $x < $width; $x++) {
            my $color = $img->getPixel($x, $y);
            my ($r, $g, $b) = $img->rgb($color);

            push(@red, $r);
            push(@green, $g);
            push(@blue, $b);
        }
    }
    return \@red, \@green, \@blue;
}

# デコードする
sub dec {
    my $filename = shift;

    my $img = &read_image($filename);
    my ($r, $g, $b) = &get_rgb($img);

    # 埋め込んであるデータのサイズ(バイト)を取得
    my $size = &get_embedded_size($r, $b);

    # 4ピクセルを使って1バイトを埋め込んでいるので
    # 画像のピクセル数に収まらないデータサイズなら
    # データは埋め込まれてないなと判断する。
    my $num_of_pixel = @$r;
    my $max_data_size = int($num_of_pixel / 4) - 2;
    if ($size > $max_data_size) {
        die("Cannot decode: $filename");
    }

    my @embedded_data = &get_data($r, $b, $size);

    print &byte_array_to_str(@embedded_data);
}

sub get_data {
    my ($r, $b, $size) = @_;

    my @ret = ();

    # 先頭2バイトにはデータの長さが書き込んであるので
    # 3バイト目から取得する
    for (2 .. (2 + $size - 1)) {
        push(@ret, &get_data_1byte($r, $b, $_));
    }

    return @ret;
}

# 埋め込まれているデータのバイト数を取得する
sub get_embedded_size {
    my ($r, $b) = @_;

    # 先頭2バイトに、埋め込んだ文字列のバイト数を書き込んである
    my $d0 = &get_data_1byte($r, $b, 0);
    my $d1 = &get_data_1byte($r, $b, 1);

    return hex(sprintf("%02X%02X", $d0, $d1));
}

sub get_data_1byte {
    my ($r, $b, $index) = @_;

    # indexバイト目のデータを取得する
    # 4ピクセルで1バイトのデータを埋め込んでいる
    my $start = $index * 4;

    my $bin = "";

    $bin .=  ($$r[$start + 0] % 2);
    $bin .=  ($$r[$start + 1] % 2);
    $bin .=  ($$r[$start + 2] % 2);
    $bin .=  ($$r[$start + 3] % 2);

    $bin .=  ($$b[$start + 0] % 2);
    $bin .=  ($$b[$start + 1] % 2);
    $bin .=  ($$b[$start + 2] % 2);
    $bin .=  ($$b[$start + 3] % 2);

    return oct("0b" . $bin);
}

sub read_image {
    my $file = shift;
    return GD::Image->newFromPng($file, 1);
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

sub _dump {
    my ($data, $width) = @_;

    my $i = 0;
    for (@$data) {
        printf("%02x ", $_);
        if (++$i >= $width) {
            print("\n");
            $i = 0;
        }
    }
}

&run;
