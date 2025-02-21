cc_dir="$(dirname "$0")"/..

export LLVM_SUFFIX=-9


build_llvm_passes() {
    make -C "$cc_dir/llvm-passes" passes.so
}

clean_llvm_passes() {
    rm -fv "$cc_dir/llvm-passes/passes.so"
}


build_picolibc() {
    mkdir -p "$cc_dir/picolibc/build"
    (
        cd "$cc_dir/picolibc/build"
        if ! [ -f build.ninja ]; then
            ../scripts/do-fromager-configure
        fi
        ninja install
    )
}

clean_picolibc() {
    rm -rf "$cc_dir/picolibc/build"
}


build_compiler_rt() {
    mkdir -p "$cc_dir/llvm-project/compiler-rt/build"
    (
        cd "$cc_dir/llvm-project/compiler-rt/build"
        if ! [ -f build.ninja ]; then
            # Setting CFLAGS=-flto is not enough, because compiler-rt tries to
            # force disable LTO via -fno-lto.  We prevent this by adding
            # -DCOMPILER_RT_HAS_FNO_LTO_FLAG=OFF.
            CC=clang${LLVM_SUFFIX} CFLAGS=-flto cmake .. -G Ninja \
                -DCMAKE_BUILD_TYPE=Release \
                -DLLVM_CONFIG_PATH=llvm-config${LLVM_SUFFIX} \
                -DCOMPILER_RT_STANDALONE_BUILD=ON \
                -DCOMPILER_RT_BAREMETAL_BUILD=ON \
                -DCOMPILER_RT_BUILD_CRT=OFF \
                -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
                -DCOMPILER_RT_BUILD_XRAY=OFF \
                -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
                -DCOMPILER_RT_BUILD_PROFILE=OFF \
                -DCOMPILER_RT_BUILD_MEMPROF=OFF \
                -DCOMPILER_RT_BUILD_ORC=OFF \
                -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
                -DCOMPILER_RT_HAS_FNO_LTO_FLAG=OFF
        fi
        ninja
        cp -v lib/*/libclang_rt.builtins-x86_64.a .
    )
}

clean_compiler_rt() {
    rm -rf "$cc_dir/llvm-project/compiler-rt/build"
}


build_microram() {
    (
        cd "$cc_dir/MicroRAM"
        stack build
    )
}

clean_microram() {
    (
        cd "$cc_dir/MicroRAM"
        stack clean
    )
}


build_witness_checker() {
    (
        cd "$cc_dir/witness-checker"
        cargo build --release --features bellman,sieve_ir
    )
}

clean_witness_checker() {
    rm -rf "$cc_dir/witness-checker/target"
}


# Examples

build_grit() {
    build_llvm_passes
    build_picolibc
    build_compiler_rt
    (
        cd "$cc_dir/grit"
        fromager/build.sh microram
    )
}

clean_grit() {
    rm -rf \
        "$cc_dir/grit/build" \
        "$cc_dir/grit/driver-link.ll" \
        "$cc_dir/grit/"lib*.a
}

run_grit() {
    build_grit
    build_microram
    build_witness_checker
    mkdir -p "$cc_dir/out/grit"
    (
        cd "$cc_dir/MicroRAM"
        if [ "$#" -lt 1 ]; then
            args="4716 --priv-segs 249"
        else
            args=$1
        fi
        # 4716 steps with public pc (baseline)
        # args="4716 --priv-segs 249"
        # no sparsity
        # args="4716 --priv-segs 249 --sparsity 1"
        # no public-pc
        # args="4716 --pub-seg-mode none"
        time stack run compile -- \
            --from-llvm ../grit/driver-link.ll \
            $args \
            --regs 11 \
            -o ../out/grit/grit.cbor \
            --verbose \
            2>&1 | tee ../out/grit/microram.log
    )
    (
        out_dir="$cc_dir/out/grit"
        cd "$cc_dir"
        time witness-checker/target/release/cheesecloth \
            --skip-backend-validation \
            --available-plugins '' \
            $out_dir/grit.cbor --boolean-sieve-ir-v2-out $out_dir/sieve \
            2>&1 | tee $out_dir/witness-checker.log
    )
}


build_ffmpeg() {
    build_llvm_passes
    build_picolibc
    build_compiler_rt
    (
        cd "$cc_dir/ffmpeg"
        [ -f config.h ] || CVE-2013-0864/configure.sh
        DRIVER_CFLAGS='-DSILENT' CVE-2013-0864/build.sh microram
    )
}

clean_ffmpeg() {
    make -C $cc_dir/ffmpeg clean

    rm -rf \
        "$cc_dir/ffmpeg/build" \
        "$cc_dir/ffmpeg/driver-link.ll" \
        "$cc_dir/ffmpeg/driver"
}

run_ffmpeg() {
    build_ffmpeg
    build_microram
    build_witness_checker
    mkdir -p "$cc_dir/out/ffmpeg"
    (
        cd "$cc_dir/MicroRAM"
        if [ "$#" -lt 1 ]; then
            args="78983 --priv-segs 6652"
        else
            args=$1
        fi
        # 78983 steps with public pc (baseline)
        # args="78983 --priv-segs 6652"
        # no sparsity
        # args="78983 --priv-segs 6652 --sparsity 1"
        # no public-pc
        # args="78983 --pub-seg-mode none"
        stack run compile -- \
            --from-llvm ../ffmpeg/driver-link.ll \
            $args \
            --regs 11 \
            -o ../out/ffmpeg/ffmpeg.cbor \
            --verbose \
            2>&1 | tee ../out/ffmpeg/microram.log
    )
    (
        out_dir="$cc_dir/out/ffmpeg"
        cd "$cc_dir"
        time witness-checker/target/release/cheesecloth \
            --skip-backend-validation \
            --available-plugins '' \
            $out_dir/ffmpeg.cbor --boolean-sieve-ir-v2-out $out_dir/sieve \
            2>&1 | tee $out_dir/witness-checker.log
    )
}

build_openssl() {
    build_llvm_passes
    build_picolibc
    build_compiler_rt
    (
        cd "$cc_dir/openssl"
        if ! [ -f libssl.a ]; then
            ./fromager-config.sh
            make depend
            make -C crypto
            make -C ssl
        fi
    )
    (
        cd "$cc_dir/openssl-driver"
        [ -f driver-link.ll ] || cc_instrument=1 cc_flatten_init=1 make all
    )
}

clean_openssl() {
    echo clean_openssl not yet implemented
    exit 1
}

run_openssl() {
    build_openssl
    build_microram
    build_witness_checker
    out_dir="$cc_dir/out/openssl"
    # out_dir="/mnt/HDD-9T/usenix2023-final/out/openssl"
    mkdir -p $out_dir
    (
        cd "$cc_dir/MicroRAM"
        if [ "$#" -lt 1 ]; then
            args="1300000 --priv-segs 110000"
        else
            args=$1
        fi
        stack run compile -- \
            --from-llvm ../openssl-driver/driver-link.ll \
            $args \
            --regs 11 \
            --mode leak-tainted \
            -o $out_dir/openssl.cbor \
            --verbose \
            2>&1 | tee $out_dir/microram.log
    )
    (
        cd "$cc_dir"
        /usr/bin/time witness-checker/target/release/cheesecloth \
            $out_dir/openssl.cbor --boolean-sieve-ir-v2-out $out_dir/sieve \
            --mode leak-tainted \
            --skip-backend-validation \
            --available-plugins '' \
            2>&1 | tee $out_dir/witness-checker.log
    )
}
