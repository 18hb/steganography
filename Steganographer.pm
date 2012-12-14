# ------------------------------------------------------------
# エンコード／デコードモジュール
# ------------------------------------------------------------
package Steganographer;

use GD;
use Data::Dumper;

sub new {
    my ($class) = shift;

    my ($pattern) = shift;
    my $px_on_1byte = @$pattern;

    my $data = {
        image => undef,
        embeddable_size => undef,
        pattern => $pattern,
        px_on_1byte => $px_on_1byte,    # 1バイトを構成するピクセル数
    };

    my $self = bless $data, $class;
    return $self;
}

sub load {
    my $self = shift;
    my $filename = shift;

    my $img = GD::Image->newFromPng($filename, 1);
    $self->{image} = $img;

    # 埋め込み可能データサイズ byte
    # (先頭2バイトはデータサイズ埋め込みに使用。)
    my $num_of_pixel = $img->width * $img->height;
    $self->{embeddable_size} = int($num_of_pixel / $self->{px_on_1byte}) - 2;
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

    my @len = ();
    push(@len, ($len >> 8));
    push(@len, ($len & 0xFF));

    # 埋め込むデータのサイズも画像に埋め込む。
    # 先頭2バイトをデータサイズとして使用。
    # (とりあえず65536バイトまで埋め込める想定)
    unshift(@$data, @len);

    my $i = 0;
    for (@$data) {
        $self->_embed_1byte($_, $i);
        $i++;
    }
}

# データ1バイトを画像データに埋め込む
#
# $data:  埋め込むデータ 1byte
# $index: 埋め込むデータが何バイト目か
sub _embed_1byte {
    my $self = shift;
    my $data = shift;
    my $index = shift;

    # データを埋め込む画素の色データ取得
    my $start = $index * $self->{px_on_1byte};
    my @rgb = $self->_get_rgb_n($start, $self->{px_on_1byte});

    # データ1バイトを、patternに展開する
    my @ex_data = $self->_expand($data);

    # 画像データへ埋め込む
    my @embedded_rgb = ();
    for (my $i = 0; $i < $self->{px_on_1byte}; $i++) {
        push @embedded_rgb, $self->_embed_to_1pixel($rgb[$i], $ex_data[$i], $self->{pattern}->[$i]);
    }

    # 埋め込んだデータをGDオブジェクトへ書き込む
    my $i = $start;
    foreach my $_rgb (@embedded_rgb) {
        $self->_set_rgb($i++, $_rgb);
    }
}

# 1バイトのデータをpatternのビットに展開する
sub _expand {
    my $self = shift;
    my $data = shift;

    my @ex_data = ();

    for my $pattern (@{$self->{pattern}}) {
        my $ex_data = 0;
        for (my $i = 0; $i < 24; $i++) {
            $ex_data <<= 1;
            if (($pattern << $i) & 0x800000) {
                $ex_data |= (($data & 0x80) > 0 ? 1 : 0);
                $data &= 0x7F; # 不要かな...
                $data <<= 1;
            }
        }
        push @ex_data, $ex_data;
    }
    return @ex_data;
}

sub _embed_to_1pixel {
    my $self = shift;
    my $rgb = shift;
    my $data = shift;
    my $mask = shift;

    my $embedded = $rgb;

    # bit1 の埋め込み
    $embedded |= ($mask & $data);

    # bit0 の埋め込み
    $embedded &= ~($mask ^ $data);

    return $embedded;
}

# 左上を0番目として、$i番目から$n画素分の色データを取得する
sub _get_rgb_n {
    my $self = shift;
    my $i = shift;
    my $n = shift;

    my @ret = ();
    for ($i .. ($i + $n - 1)) {
        my $rgb = $self->_get_rgb($_);
        push @ret, $rgb;
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

    return (($r << 16) | ($g << 8) | $b);
}

# 左上を0番目として、$i番目の画素に色をセットする
sub _set_rgb {
    my $self = shift;
    my $i = shift;
    my $rgb = shift;

    my $r = $rgb >> 16;
    my $g = ($rgb >> 8) & 0xFF;
    my $b = $rgb & 0xFF;

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

    if ($size > $self->{embeddable_size}) {
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
    for (my $i = 2; $i < 2 + $size; $i++) {
        push @ret, $self->_get_data_1byte($i);
    }
    return @ret;
}

# 画像に埋め込まれているデータの$indexバイト目を取得する
# (制限: 1ピクセルに2バイト以上のデータは埋め込めない)
sub _get_data_1byte {
    my $self = shift;
    my $index = shift;

    my $start = $index * $self->{px_on_1byte};

    my @rgb = $self->_get_rgb_n($start, $self->{px_on_1byte});

    my $mask = 0x800000;
    my $data = 0;

    for (my $i = 0;  $i < $self->{px_on_1byte}; $i++) {
        my $p = $self->{pattern}->[$i];

        for (my $shift = 0; $shift < 24; $shift++) {
            if ($p & ($mask >> $shift)) {
                my $bit = ((($mask >> $shift) & $rgb[$i]) > 0 ? 1 : 0);
                $data = ($data << 1) | $bit;
            }
        }
    }

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

1;
