ENTRY(_start)

SECTIONS
{
    . = 1M;

    .text : {
        *(.text .text.*)
    }

    .data : {
        *(.data .data.*)
    }

    .rodata : {
        *(.rodata .rodata.*)
    }

    .bss : {
        *(.bss .bss.*)
    }

    /* Rust sections */
    .text.rust : {
        *(.text.rust*)
        *(.rodata.rust*)
    }

    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.comment)
        *(.note)
    }
}
