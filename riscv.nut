// Copyright 2022 Joshua Ashton, you may use this file or any portions herein under any of the BSD, MIT, or CC0 licenses.
//
// Based on mini-rv32ima by Charles Lohr, license as follows:
//   Copyright 2022 Charles Lohr, you may use this file or any portions herein under any of the BSD, MIT, or CC0 licenses.
//
// This is basically just a raw port of mini-rv32ima to Squirrel3.
// Rather annoying as Squirrel has no fixed/small size or unsigned types... only >>> for unsigned shift. (ie. non-sign-extend)
// So we have to emulate all of that and all the logic for it is 'fun'.
// We map the player_say game event to map player text to the UART interface.
//
// It supports basically everything you could ever want, but do
// not consider it in any way conformant.
// It can boot the Linux kernel, run coremark, run sha256sum and get
// a correct results, etc.
// It can even shutdown with `halt -f` and it actually shuts down
// the risc-v computer and cleans up the entity responsible for
// the Think function.
//
//
// I was very close to giving up many times writing this code.
// Luckily mini-rv32ima has a single-step register dump mode.
// All of the debugging was done via enabling single-step, and a fixed elapsed_us
// and diff-ing the single-step outputs to see where we diverge.
//
// Special thanks to cnlohr for nerdsniping me with this tiny rv32 implementation
// I was very surprised how understandable it was, and how little it takes
// to have a rv32 implementation capable of actually being usable!
//
// This code was all made in a tea-infused 6 hour coding session.
//

ram_image_offset <- 0x80000000;
ram_size <- 16 * 1024 * 1024;

function r32_val_size_sign_bit( val_size )
{
    if ( val_size == 1 )
    {
        return 0x80;
    }
    else if ( val_size == 2 )
    {
        return 0x8000;
    }
    else
    {
        return 0x80000000;
    }
}

function r32_val_size_mask( val_size )
{
    if ( val_size == 4 )
    {
        return 0xffffffff;
    }
    else if ( val_size == 2 )
    {
        return 0x0000ffff;
    }
    else
    {
        return 0x000000ff;
    }
}

function rv32_load1( image, ofs )
{
    image.seek( ofs, 'b' );
    return image.readn( 'b' );
}

function rv32_load2( image, ofs )
{
    image.seek( ofs, 'b' );
    return image.readn( 'w' );
}

function rv32_load4( image, ofs )
{
    image.seek( ofs, 'b' );
    return image.readn( 'i' );
}

function rv32_store1( image, ofs, val )
{
    image.seek( ofs, 'b' );
    return image.writen( val & 0xff, 'b' );
}

function rv32_store2( image, ofs, val )
{
    image.seek( ofs, 'b' );
    return image.writen( val & 0xffff, 'w' );
}

function rv32_store4( image, ofs, val )
{
    image.seek( ofs, 'b' );
    return image.writen( val, 'i' );
}

// Josh: Emulate 32-bit unsigned less than by
// splitting the number into two 16-bit components.
function rv32_unsigned_lt( x, y )
{
    local x_lower = x & 0x0000ffff;
    local x_upper = ( x >>> 16 ) & 0x0000ffff;

    local y_lower = y & 0x0000ffff;
    local y_upper = ( y >>> 16 ) & 0x0000ffff;

    if ( x_upper == y_upper )
        return x_lower < y_lower;

    return x_upper < y_upper;
}

function rv32_unsigned_ge( x, y )
{
    return !rv32_unsigned_lt( x, y );
}

function rv32_unsigned_add( x, y )
{
    return x + y;
}

function rv32_unsigned_sub( x, y )
{
    return x - y;
}

function rv_debug_printl( str )
{
    //printl( str );
}

function rv32_unsigned_mul( x, y )
{
    return x * y;
}

function rv32_signed_mulh( x, y )
{
    // Josh: Using signed (sign-extend) shifts here.
    local x0 = x & 0x0000ffff;
    local x1 = x >> 16;

    local y0 = y & 0x0000ffff;
    local y1 = y >> 16;

    local p11 = x1 * y1;
    local p01 = x0 * y1;
    local p10 = x1 * y0;
    local p00 = x0 * y0;

    local middle = p10 + (p00 >> 16) + (p01 & 0x0000ffff);

    local hi = p11 + (middle >> 16) + (p01 >> 16);
    return hi;
}

function rv32_mixed_mulh( x_int, y_unsigned )
{
    // TODO!
    // Haven't seen anything use this yet.
    rv_debug_printl( "rv32_mixed_mulh" );
    return 0;
}

// Josh: Emulate getting the high of a 32-bit mul
// by treating it as 16-bit parts.
//
// This feels stupid...
// Maybe it is the only way or the best way
// but I don't know -- it is still stupid.
function rv32_unsigned_mulh( x, y )
{
    local x0 = x & 0x0000ffff;
    local x1 = x >>> 16;

    local y0 = y & 0x0000ffff;
    local y1 = y >>> 16;

    local p11 = x1 * y1;
    local p01 = x0 * y1;
    local p10 = x1 * y0;
    local p00 = x0 * y0;

    local middle = p10 + (p00 >>> 16) + (p01 & 0x0000ffff);

    local hi = p11 + (middle >>> 16) + (p01 >>> 16);
    return hi;
}

function rv32_unsigned_div( x, y )
{
    // Josh: No way in hell this is correct.
    // I pulled all of this logic out my ass.
    // Good enough to login though!
    if ( x == y )
        return 1;

    local val = x / y;
    if ( ( !!( x & 0x80000000 ) ) != ( !!( y & 0x80000000 ) ) )
    {
        val = val ^ 0x80000000;
    }
    return val;
}

function rv32_unsigned_mod( x, y )
{
    // TODO!
    // Stuff uses this, but I haven't
    // seen anything rely on the different
    // semantics with signed-ness yet.
    rv_debug_printl( "rv32_unsigned_mod" );
    return x % y;
}

function rv32_sign_extend( x, val_size )
{
    if ( x & r32_val_size_sign_bit( val_size ) )
    {
        x = x | ~( r32_val_size_mask( val_size ) );
    }

    return x;
}

// Callbacks

player_input_buffer <- ""

function OnGameEvent_player_say( params )
{
    player_input_buffer = player_input_buffer + params.text + "\n";
}

__CollectGameEventCallbacks( this )

function rv32_print_output( str )
{
    print( str )
}

function rv32_is_keyboard_hit()
{
    return player_input_buffer.len() != 0 ? 1 : 0;
}

function rv32_read_keyboard_byte()
{
    local input_byte = player_input_buffer[0];
    player_input_buffer = player_input_buffer.slice(1);
    return input_byte;
}

function rv32_handle_mem_load_control( rsval, rval )
{
	// Emulating a 8250 / 16550 UART
	if( rsval == 0x10000005 )
		return 0x60 | rv32_is_keyboard_hit();
	else if( rsval == 0x10000000 && rv32_is_keyboard_hit() )
		return rv32_read_keyboard_byte();
	return 0;
}

function rv32_handle_mem_store_control( addy, rs2 )
{
    if ( addy == 0x10000000 ) //UART 8250 / 16550 Data Buffer
    {
        rv32_print_output( rs2.tochar() );
    }
    return 0;
}

function rv32_othercsr_read( state, csrno, rval )
{
    return rval;
}

function rv32_othercsr_write( state, image, csrno, value )
{
	if( csrno == 0x136 )
	{
        // Print number
        rv32_print_output( value );
	}
	else if ( csrno == 0x137 )
	{
        // Print hex
		rv32_print_output( format( "%08x", value ) );
	}
	else if( csrno == 0x138 )
	{
		//Print "string"
		local ptrstart = rv32_unsigned_sub( value, ram_image_offset );
		local ptrend = ptrstart;
		while( ptrend < ram_size )
		{
			if( image[ ptrend ] == 0 )
                break;
			ptrend++;
		}

        if ( ptrend == ptrstart )
        {
            rv_debug_printl( "DEBUG PASSED INVALID PTR " + value + "\n" );
            return;
        }

        for ( local i = ptrstart; i < ptrend; i++ )
        {
            rv32_print_output( image[ i ].tochar() );
        }
	}
}

function rv32_handle_exception( ir, trap )
{
    rv_debug_printl( "exception: " + trap )
    if ( trap == 3 ) // invalid opcode
        trap.test = 4; // cause a fault on sq side
    return trap;
}

function rv32_post_exec( pc, ir, trap )
{
    if ( trap > 0 )
        trap = rv32_handle_exception( ir, trap );
    
    return trap;
}

//

function rv32_create_state_object( pc, dtb_ptr )
{
    local state = {};

    // Initialize state
    state.regs <- [];
    for ( local i = 0; i < 32; i++ )
        state.regs.append( 0 );
    state.regs[11] = dtb_ptr;
    state.pc <- pc;
    state.cycleh <- 0;
    state.cyclel <- 0;
    state.mstatus <- 0;
    state.timerh <- 0;
    state.timerl <- 0;
    state.timermatchh <- 0;
    state.timermatchl <- 0;
    state.mscratch <- 0;
    state.mtvec <- 0;
    state.mie <- 0;
    state.mip <- 0;
    state.mepc <- 0;
    state.mtval <- 0;
    state.mcause <- 0;
    state.extraflags <- 3; // Machine mode

    return state;
}

function rv32_ima_step( state, image, proc_address, elapsed_us, count )
{
    local new_timer = rv32_unsigned_add( state.timerl, elapsed_us );
    if ( rv32_unsigned_lt( new_timer, state.timerl ) )
        state.timerh = rv32_unsigned_add( state.timerh, 1 );
    state.timerl = new_timer;

    if ( ( state.timerh > state.timermatchh || ( state.timerh == state.timermatchh && state.timerl > state.timermatchl ) ) && ( state.timermatchh || state.timermatchl ) )
    {
        state.extraflags = state.extraflags & (~4);
        state.mip = state.mip | ( 1 << 7 );
    }
    else
    {
        state.mip = state.mip & ( ~( 1 << 7 ) );
    }

    if ( state.extraflags & 4 )
    {
        return 1;
    }

    for ( local icount = 0; icount < count; icount++ )
    {
        local ir = 0;
        local trap = 0;
        local rval = 0;

        state.cyclel = rv32_unsigned_add( state.cyclel, 1 );
        if ( state.cyclel == 0 )
            state.cycleh = rv32_unsigned_add( state.cycleh, 1 );

        local pc = state.pc;
        local ofs_pc = pc - ram_image_offset;

        if ( rv32_unsigned_ge( ofs_pc, ram_size ) )
        {
            trap = 1 + 1;
        }
        else if ( ofs_pc & 3 )
            trap = 1 + 0;
        else
        {
            ir = rv32_load4( image, ofs_pc );
            local rdid = ( ir >>> 7 ) & 0x1f;

            switch ( ir & 0x7f )
            {
                case 0x37: // LUI
                    rval = ( ir & 0xfffff000 );
                    break;
                case 0x17: // AUIPC
                    rval = pc + ( ir & 0xfffff000 );
                    break;
                case 0x6F: // JAL
                {
                    local reladdy =  ( ( ir & 0x80000000 ) >>> 11 ) | ( ( ir & 0x7fe00000 ) >>> 20 ) | ( ( ir & 0x00100000 ) >>> 9 ) | ( ( ir & 0x000ff000 ) );
                    if ( reladdy & 0x00100000 )
                    {
                        reladdy = reladdy | 0xffe00000; // Sign extension.
                    }
                    rval = pc + 4;
                    pc = pc + reladdy - 4;
                    break;
                }
                case 0x67: // JALR
                {
                    local imm = ir >>> 20;
                    local imm_se = imm | ( ( imm & 0x800 ) ? 0xfffff000 : 0 );
                    rval = pc + 4;
                    pc = ( (state.regs[ ( ir >>> 15 ) & 0x1f ] + imm_se ) & ~1 ) - 4;
                    break;
                }
                case 0x63: // Branch
                {
                    local immm4 = ( ( ir & 0xf00 ) >>> 7 ) | ( ( ir & 0x7e000000 ) >>> 20 ) | ( ( ir & 0x80 ) << 4 ) | ( ( ir >>> 31 ) << 12 );
                    if ( immm4 & 0x1000 )
                    {
                        immm4 = immm4 | 0xffffe000;
                    }
                    local rs1 = state.regs[ ( ir >>> 15 ) & 0x1f ];
                    local rs2 = state.regs[ ( ir >>> 20 ) & 0x1f ];
                    immm4 = pc + rv32_unsigned_sub(immm4, 4);
                    rdid = 0;
                    //printl(format( "rs1: %08x rs2: %08x immm4: %08x op: %08x ge: %08x", rs1, rs2, immm4, (( ir >>> 12 ) & 0x7), rv32_unsigned_ge( rs1, rs2 ) ? 1 : 0));
                    switch( ( ir >>> 12 ) & 0x7 )
                    {
                        // BEQ, BNE, BLT, BGE, BLTU, BGEU 
                        case 0x0: if( rs1 == rs2 ) pc = immm4; break;
                        case 0x1: if( rs1 != rs2 ) pc = immm4; break;
                        case 0x4: if( rs1 < rs2 ) pc = immm4; break;
                        case 0x5: if( rs1 >= rs2 ) pc = immm4; break; //BGE
                        case 0x6: if( rv32_unsigned_lt( rs1, rs2 ) ) pc = immm4; break;   //BLTU
                        case 0x7: if( rv32_unsigned_ge( rs1, rs2 ) ) pc = immm4; break;  //BGEU
                        default:
                        {
                            rv_debug_printl( "Hit undefined opcode in branch" );
                            trap = ( 2 + 1 );
                        }
                    }
                    break;
                }
                case 0x3: // Load
                {
                    local rs1 = state.regs[ ( ir >>> 15 ) & 0x1f ];
                    local imm = ir >>> 20;
                    local imm_se = imm | ( ( imm & 0x800 ) ? 0xfffff000 : 0 );
                    local rsval = rv32_unsigned_add( rs1, imm_se );

                    rsval = rv32_unsigned_sub( rsval, ram_image_offset );
                    if ( rv32_unsigned_ge( rsval, rv32_unsigned_sub( ram_size, 3 ) ) )
                    {
                        rsval = rv32_unsigned_sub( rsval, ram_image_offset )
                        if ( rv32_unsigned_ge( rsval, 0x10000000 ) && rv32_unsigned_lt( rsval, 0x12000000 ) ) // UART, CLNT
                        {
                            if ( rsval == 0x1100bffc ) // https://chromitem-soc.readthedocs.io/en/latest/clint.html
                            {
                                rval = state.timerh;
                            }
                            else if ( rsval == 0x1100bff8 )
                            {
                                rval = state.timerl;
                            }
                            else
                            {
                                rval = rv32_handle_mem_load_control( rsval, rval );
                            }
                        }
                        else
                        {
                            trap = 5 + 1;
                            rval = rsval;
                        }
                    }
                    else
                    {
                        switch( ( ir >>> 12 ) & 0x7 )
                        {
                            //LB, LH, LW, LBU, LHU
                            case 0x0: rval = rv32_sign_extend( rv32_load1( image, rsval ), 1 ); break;
                            case 0x1: rval = rv32_sign_extend( rv32_load2( image, rsval ), 2 ); break;
                            case 0x2: rval = rv32_load4( image, rsval ); break;
                            case 0x4: rval = rv32_load1( image, rsval ); break;
                            case 0x5: rval = rv32_load2( image, rsval ); break;
                            default: trap = 2+1; break;
                        }
                    }
                    break;
                }
                case 0x23: // Store
                {
                    local rs1 = state.regs[ ( ir >>> 15 ) & 0x1f ];
                    local rs2 = state.regs[ ( ir >>> 20 ) & 0x1f ];
                    local addy = ( ( ir >>> 7 ) & 0x1f ) | ( ( ir & 0xfe000000 ) >>> 20 );
                    if( addy & 0x800 )
                    {
                        addy = addy | 0xfffff000;
                    }

                    addy = rv32_unsigned_add( addy, rv32_unsigned_sub( rs1, ram_image_offset ) );
                    rdid = 0;

                    if ( rv32_unsigned_ge( addy, rv32_unsigned_sub( ram_size, 3 ) ) )
                    {
                        local prev_addy = addy;
                        addy = rv32_unsigned_sub( addy, ram_image_offset );
                        if ( rv32_unsigned_ge( addy, 0x10000000 ) && rv32_unsigned_lt( addy, 0x12000000 ) )
                        {
                            // Should be stuff like SYSCON, 8250, CLNT
                            if ( addy == 0x11004004 ) //CLNT
                            {
                                state.timermatchh = rs2;
                            }
                            else if ( addy == 0x11004000 ) //CLNT
                            {
                                state.timermatchl = rs2;
                            }
                            else if ( addy == 0x11100000 ) //SYSCON (reboot, poweroff, etc.)
                            {
                                state.pc = rv32_unsigned_add( pc, 4 );
                                return rs2; // NOTE: PC will be PC of Syscon.
                            }
                            else
                            {
                                if ( rv32_handle_mem_store_control( addy, rs2 ) )
                                {
                                    return rs2;
                                }
                            }
                        }
                        else
                        {
                            trap = 7 + 1;
                            rval = rv32_unsigned_add( addy, ram_image_offset );
                        }
                    }
                    else
                    {
                        switch( ( ir >>> 12 ) & 0x7 )
                        {
                            //SB, SH, SW
                            case 0x0: rv32_store1( image, addy, rs2 ); break;
                            case 0x1: rv32_store2( image, addy, rs2 ); break;
                            case 0x2: rv32_store4( image, addy, rs2 ); break;
                            default:
                            {
                                rv_debug_printl( "Hit undefined opcode in store" );
                                trap = 2 + 1;
                                break;
                            }
                        }
                    }
                    break
                }
                case 0x13: // Op-immediate
                case 0x33: // Op
                {
                    local imm = ir >>> 20;
                    imm = imm | ( ( imm & 0x800 ) ? 0xfffff000 : 0 );
                    local rs1 = state.regs[ ( ir >>> 15 ) & 0x1f ];
                    local is_reg = ( ir & 0x20 ) != 0;
                    local rs2 = is_reg ? state.regs[ imm & 0x1f ] : imm;

                    if ( is_reg && ( ir & 0x02000000 ) )
                    {
                        switch( ( ir >>> 12 ) & 7 ) //0x02000000 = RV32M
                        {
                            case 0x0: rval = rv32_unsigned_mul( rs1, rs2 ); break; // MUL
                            case 0x1: rval = rv32_signed_mulh( rs1, rs2 ); break; // MULH
                            case 0x2: rval = rv32_mixed_mulh( rs1, rs2 ); break; // MULHSU
                            case 0x3: rval = rv32_unsigned_mulh( rs1, rs2 ) >>> 32; break; // MULHU
                            case 0x4: if( rs2 == 0 ) rval = -1; else rval = rs1 / rs2; break; // DIV
                            case 0x5: if( rs2 == 0 ) rval = 0xffffffff; else rval = rv32_unsigned_div( rs1, rs2 ); break; // DIVU
                            case 0x6: if( rs2 == 0 ) rval = rs1; else rval = rs1 % rs2; break; // REM
                            case 0x7: if( rs2 == 0 ) rval = rs1; else rval = rv32_unsigned_mod( rs1, rs2 ); break; // REMU
                        }
                    }
                    else
                    {
                        switch( ( ir >>> 12 ) & 7 ) // These could be either op-immediate or op commands.  Be careful.
                        {
                            case 0x0: rval = (is_reg && ( ir & 0x40000000 ) ) ? ( rs1 - rs2 ) : ( rs1 + rs2 ); break;
                            case 0x1: rval = rs1 << rs2; break;
                            case 0x2: rval = ( rs1 < rs2 ) ? 1 : 0; break;
                            case 0x3: rval = rv32_unsigned_lt( rs1, rs2 ) ? 1 : 0; break;
                            case 0x4: rval = rs1 ^ rs2; break;
                            // Note(Josh): >>> is unsigned shift right, >> is signed shift right
                            case 0x5: rval = ( ir & 0x40000000 ) ? ( rs1 >> rs2 ) : ( rs1 >>> rs2 ); break;
                            case 0x6: rval = rs1 | rs2; break;
                            case 0x7: rval = rs1 & rs2; break;
                        }
                    }
                    break;
                }
                case 0xF:
                    rdid = 0; // We ignore fences in this impl.
                    break;
                case 0x73: // Zifencei+Zicsr
                {
                    local csrno = ir >> 20;
                    local microop = ( ir >> 12 ) & 0x7;
                    if ( microop & 3 )
                    {
                        local rs1imm = ( ir >> 15 ) & 0x1f;
                        local rs1 = state.regs[ rs1imm ];
                        local writeval = rs1;

                        // https://raw.githubusercontent.com/riscv/virtual-memory/main/specs/663-Svpbmt.pdf
                        // Generally, support for Zicsr
                        switch( csrno )
                        {
                            case 0x340: rval = state.mscratch; break;
                            case 0x305: rval = state.mtvec; break;
                            case 0x304: rval = state.mie; break;
                            case 0xC00: rval = state.cyclel; break;
                            case 0x344: rval = state.mip; break;
                            case 0x341: rval = state.mepc; break;
                            case 0x300: rval = state.mstatus; break; //mstatus
                            case 0x342: rval = state.mcause; break;
                            case 0x343: rval = state.mtval; break;
                            case 0xf11: rval = 0xff0ff0ff; break; //mvendorid
                            case 0x301: rval = 0x40401101; break; //misa (XLEN=32, IMA+X)
                            //case 0x3B0: rval = 0; break; //pmpaddr0
                            //case 0x3a0: rval = 0; break; //pmpcfg0
                            //case 0xf12: rval = 0x00000000; break; //marchid
                            //case 0xf13: rval = 0x00000000; break; //mimpid
                            //case 0xf14: rval = 0x00000000; break; //mhartid
                            default:
                                rval = rv32_othercsr_read( state, csrno, rval );
                                break;
                        }

                        switch( microop )
                        {
                            case 0x1: writeval = rs1; break;            //CSRRW
                            case 0x2: writeval = rval | rs1; break;     //CSRRS
                            case 0x3: writeval = rval & ~rs1; break;    //CSRRC
                            case 0x5: writeval = rs1imm; break;         //CSRRWI
                            case 0x6: writeval = rval | rs1imm; break;  //CSRRSI
                            case 0x7: writeval = rval & ~rs1imm; break; //CSRRCI
                        }

                        switch( csrno )
                        {
                            case 0x340: state.mscratch = writeval; break;
                            case 0x305: state.mtvec = writeval; break;
                            case 0x304: state.mie = writeval; break;
                            case 0x344: state.mip = writeval; break;
                            case 0x341: state.mepc = writeval; break;
                            case 0x300: state.mstatus = writeval; break; //mstatus
                            case 0x342: state.mcause = writeval; break;
                            case 0x343: state.mtval = writeval; break;
                            //case 0x3a0: break; //pmpcfg0
                            //case 0x3B0: break; //pmpaddr0
                            //case 0xf11: break; //mvendorid
                            //case 0xf12: break; //marchid
                            //case 0xf13: break; //mimpid
                            //case 0xf14: break; //mhartid
                            //case 0x301: break; //misa
                            default:
                                rv32_othercsr_write( state, image, csrno, writeval );
                                break;
                        }
                    }
                    else if ( microop == 0x0 ) // "SYSTEM"
                    {
                        rdid = 0;
                        if ( csrno == 0x105 ) //WFI (Wait for interrupts)
                        {
                            state.mstatus = state.mstatus | 8;    //Enable interrupts
                            state.extraflags = state.extraflags | 4; //Infor environment we want to go to sleep.
                            state.pc = rv32_unsigned_add( pc, 4 );
                            return 1;
                        }
                        else if( ( ( csrno & 0xff ) == 0x02 ) )  // MRET
                        {
                            //https://raw.githubusercontent.com/riscv/virtual-memory/main/specs/663-Svpbmt.pdf
                            //Table 7.6. MRET then in mstatus/mstatush sets MPV=0, MPP=0, MIE=MPIE, and MPIE=1. La
                            // Should also update mstatus to reflect correct mode.
                            local startmstatus = state.mstatus;
                            local startextraflags = state.extraflags;
                            state.mstatus = ( ( startmstatus & 0x80 ) >>> 4 ) | ( ( startextraflags & 3 ) << 11 ) | 0x80;
                            state.extraflags = ( startextraflags & ~3 ) | ( ( startmstatus >>> 11 ) & 3 );
                            pc = rv32_unsigned_sub( state.mepc, 4 );
                        }
                        else
                        {
                            switch( csrno )
                            {
                                case 0: trap = ( state.extraflags & 3 ) ? ( 11 + 1 ) : ( 8 + 1 ); break; // ECALL; 8 = "Environment call from U-mode"; 11 = "Environment call from M-mode"
                                case 1:	trap = 3 + 1; break; // EBREAK 3 = "Breakpoint"
                                default:
                                {
                                    // Illegal opcode.
                                    rv_debug_printl( "Hit illegal opcode in Zifencei+Zicsr" );
                                    trap = 2 + 1;
                                    break;
                                }
                            }
                        }
                    }
                    else
                    {
                        rv_debug_printl( "Hit undefined micro op in Zifencei+Zicsr" );
                        trap = 2 + 1; // Note micrrop 0b100 == undefined.
                    }
                    break;
                }
                case 0x2F: // RV32A
                {
                    local rs1 = state.regs[ ( ir >> 15 ) & 0x1f ];
                    local rs2 = state.regs[ ( ir >> 20 ) & 0x1f ];
                    local irmid = ( ir >> 27 ) & 0x1f;

                    rs1 = rv32_unsigned_sub( rs1, ram_image_offset );

                    if ( rv32_unsigned_ge( rs1, rv32_unsigned_sub( ram_size, 3 ) ) )
                    {
                        printl( format("RV32A Store Access Fault: %08x", rs1 ) );
                        trap = 7 + 1; // Store/AMO access fault
                        rval = rv32_unsigned_add( rs1, ram_image_offset );
                    }
                    else
                    {
                        rval = rv32_load4( image, rs1 );

                        local dowrite = true;
                        switch( irmid )
                        {
                            case 0x2: dowrite = 0; break; //LR.W
                            case 0x3: rval = 0; break; //SC.W (Lie and always say it's good)
                            case 0x1: break; //AMOSWAP.W
                            case 0x0: rs2 += rval; break; //AMOADD.W
                            case 0x4: rs2 = rs2 ^ rval; break; //AMOXOR.W
                            case 0xC: rs2 = rs2 & rval; break; //AMOAND.W
                            case 0x8: rs2 = rs2 | rval; break; //AMOOR.W
                            case 0x10: rs2 = ( rs2 < rval ) ? rs2 : rval; break; //AMOMIN.W
                            case 0x14: rs2 = ( rs2 > rval ) ? rs2 : rval; break; //AMOMAX.W
                            case 0x18: rs2 = rv32_unsigned_lt( rs2, rval ) ? rs2 : rval; break; //AMOMINU.W
                            case 0x1C: rs2 = rv32_unsigned_lt( rval, rs2 ) ? rs2 : rval; break; //AMOMAXU.W
                            default:
                            {
                                rv_debug_printl( "Hit undefined opcode in RV32A" );
                                trap = ( 2 + 1 ); dowrite = false; break; //Not supported.
                            }
                        }
                        if ( dowrite )
                        {
                            rv32_store4( image, rs1, rs2 );
                        }
                    }
                    break;
                }
                default:
                {
                    rv_debug_printl( "Hit invalid opcode" );
                    trap = 2 + 1; // Fault: Invalid opcode.
                    break;
                }
            }

            if ( trap == 0 )
            {
                if ( rdid )
                {
                    state.regs[ rdid ] = rval;
                }
                else if( ( state.mip & ( 1 << 7 ) ) && ( state.mie & ( 1 << 7 ) /*mtie*/ ) && ( state.mstatus & 0x8 /*mie*/) )
                {
					trap = 0x80000007; // Timer interrupt.
                }
            }
        }

        trap = rv32_post_exec( pc, ir, trap );

        if ( trap )
        {
            if ( trap & 0x80000000 )
            {
                state.mcause = trap;
                state.mtval = 0;
                pc += 4;
            }
            else
            {
                state.mcause = rv32_unsigned_sub( trap, 1 );
                state.mtval = rv32_unsigned_lt( 5, trap ) && rv32_unsigned_ge( 8, trap ) ? rval : pc;
            }
            state.mepc = pc;
            state.mstatus = ( ( state.mstatus & 0x08 ) << 4 ) | ( ( state.extraflags & 3 ) << 11 );
            pc = rv32_unsigned_sub( state.mtvec, 4 );

            if ( ( trap & 0x80000000 ) == 0 )
            {
                state.extraflags = state.extraflags | 3;
            }
        }

        state.pc = rv32_unsigned_add( pc, 4 );
    }

    return 0;
}

IncludeScript( "riscv_data.nut", this );

function InitComputer( computer_object )
{
    computer_object["ram_image"] <- blob( ram_size );
    local ram_image = computer_object["ram_image"]

    local dtb_size = dtb_data.len();
    local dtb_ptr = ram_size - dtb_size - 192; // 192 == sizeof( MiniRV32IMAState ) -- we do this to match output from normal mini-rv32ima as it has the MiniRV32IMAState at the end for comparing single-step.
    for ( local i = 0; i < dtb_size; i++ )
    {
        ram_image.seek( dtb_ptr + i, 'b' );
        ram_image.writen( dtb_data[i], 'b' );
    }

    local linux_size = linux_data.len();
    local linux_ptr = 0;
    for ( local i = 0; i < linux_size; i++ )
    {
        ram_image.seek( linux_ptr + i, 'b' );
        ram_image.writen( linux_data[i], 'b' );
    }

    // Patch DTB to account for ram_size
    {
        ram_image.seek( dtb_ptr + 0x13c, 'b' )
        // Validate we are using the stock DTB where this works.
        printl( "Checking if DTB should be patched..." );
        local dtb_ram = ram_image.readn( 'i' );
        printl( "Current DTB raw ram value: " + dtb_ram );
        if ( dtb_ram == 0x00c0ff03 )
        {
            local valid_ram = dtb_ptr;
            dtb_ram = ( valid_ram >>> 24 ) | ( ( ( valid_ram >>> 16 ) & 0xff ) << 8 ) | ( ( ( valid_ram >>> 8 ) & 0xff ) << 16 ) | ( ( valid_ram & 0xff ) << 24 );
            ram_image.seek( dtb_ptr + 0x13c, 'b' )
            ram_image.writen( dtb_ram, 'i' )
            printl( format( "Patched DTB to have %u (%08x) bytes of valid RAM", valid_ram, dtb_ram ) );
        }
    }

    computer_object["state"] <- rv32_create_state_object( ram_image_offset, dtb_ptr ? ( dtb_ptr + ram_image_offset ) : 0 );
    computer_object["last_time"] <- Time();
}

function ComputerSingleStepDebug()
{
    local pc = state.pc;
    local pc_offset = state.pc - ram_image_offset;

    local ignore = pc == 0x800000b0 || pc == 0x800000b4 || pc == 0x800000b8;
    if ( !ignore )
    {
        print( format( "PC: %08x ", state.pc ) );
        if ( rv32_unsigned_lt( pc_offset, rv32_unsigned_sub( ram_image_offset, 3 ) ) )
        {
            ram_image.seek( pc_offset, 'b' );
            local ir = ram_image.readn( 'i' );
            print( format( "[0x%08x] ", ir ) ); 

            // INTEGRITY
            //ram_image_bak.seek( pc_offset, 'b' );
            //local ir2 = ram_image_bak.readn( 'i' );
            //
            //if (ir != ir2)
            //    print( format( " [!!! 0x%08x] ", ir2 ) ); 
        }
        else
        {
            print( "[xxxxxxxxxx] " ); 
        }

        print( format( "Z:%08x ra:%08x sp:%08x gp:%08x tp:%08x t0:%08x t1:%08x t2:%08x s0:%08x s1:%08x a0:%08x a1:%08x a2:%08x a3:%08x a4:%08x a5:%08x ",
            state.regs[0], state.regs[1], state.regs[2], state.regs[3], state.regs[4], state.regs[5], state.regs[6], state.regs[7],
            state.regs[8], state.regs[9], state.regs[10], state.regs[11], state.regs[12], state.regs[13], state.regs[14], state.regs[15] ) );
        print( format( "a6:%08x a7:%08x s2:%08x s3:%08x s4:%08x s5:%08x s6:%08x s7:%08x s8:%08x s9:%08x s10:%08x s11:%08x t3:%08x t4:%08x t5:%08x t6:%08x\n",
            state.regs[16], state.regs[17], state.regs[18], state.regs[19], state.regs[20], state.regs[21], state.regs[22], state.regs[23],
            state.regs[24], state.regs[25], state.regs[26], state.regs[27], state.regs[28], state.regs[29], state.regs[30], state.regs[31] ) );

        //print( "EXTENDED_DEBUG:" )
        //for (local i = 0; i < 32; i++)
        //{
        //    print( " regs[" + i + "] = typeof(" + typeof( state.regs[i] ) + ")" );
        //}
        //print( "\n" );
    }
}

function CreateComputer()
{
    local riscv_computer = SpawnEntityFromTable("info_target", { targetname = "riscv_computer" } )
    if( riscv_computer.ValidateScriptScope() )
    {
        InitComputer( riscv_computer.GetScriptScope() );

        riscv_computer.GetScriptScope()["Think"] <- function()
        {
            local single_step = false;
            local instrs_per_flip = single_step ? 1 : 1024;
            local instr_count = single_step ? 32768 * 32 : 1;

            //local time = Time();
            //local dt = time - last_time;
            //last_time = time;
            //local elapsed_us = (dt * 1000000.0).tointeger();

            // Josh: Seems better to fix this to a large but not too
            // large number per-tick to make clock-training, etc go faster.
            local elapsed_us = 500;
        
            for ( local i = 0; i < instr_count; i++ )
            {
                //if ( single_step )
                //{
                    //ComputerSingleStepDebug();
                //}
        
                local ret = rv32_ima_step( state, ram_image, 0, elapsed_us, instrs_per_flip ); // Execute upto 1024 cycles before breaking out.
                switch( ret )
                {
                    case 0: break;
                    case 1: break; // sleep
                    case 0x7777: printl( "Restart requested, but cannot. Shutting down instead..." ); self.Kill(); break;
                    case 0x5555: printl( "Shutting down..." ); self.Kill(); break;
                    default: printl( "Unknown failure" ); break;
                }
            }

            return 0.001;
        }
        AddThinkToEnt( riscv_computer, "Think" )
    }
    
}

CreateComputer();
