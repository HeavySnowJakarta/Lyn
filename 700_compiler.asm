;此文件为编译器，用于将一段字符串编译成可运行程序
[bits 32]
SECTION compiler_code vstart=0
program_length dd program_end
jmp start
program_linear_address dd 0x0000_0000   ;程序的起始线性地址

common_service_entry dd 0x0000_0000
                    dw 0x0000       ;公共服务选择子

start:
;------------------------------------------------------------
;显示例程的入口函数。系统通过此函数指定功能号完成显示例程的功能调用。
;@params:  di，指定功能号
;          si,参数传递
;@return:di  如果是有数据返回的函数，则返回在这里
;使用方式：远程调用
;注意，在使用过程中，不一定需要传递参数。如果需要参数的，si直接给出参数的准确位置。
;这就要求si要跳过所有的空格字符直到下一个可打印字符。不同的函数将对si做不同的解析。

funtions_entry:
    ;第一步，比较di的值，如果有该功能标号，则进行调用。否则退出。
    cmp edi,0x01    ;1号功能，显示字符功能。最常用的可以放在前面，加快运行速度
        je initialize
    cmp edi,0x02
        je compileCommandLine    ;编译命令行与编译文本文档采用不同的风格。
    cmp edi,0x03
        je compileSourceCode    ;编译文本文件,并在缓冲区中生成相关的应用程序。
       
.exit:
    xor di,di
    retf

;-------------------------------------------------------
initialize:
    push ebx
    mov dword ebx,[cs:program_linear_address]
    mov word [ds:ebx+common_service_entry+0x04],ax
    pop ebx
    retf


;-------------------------------------------------------
;此函数用于编译一个命令行命令。编译到0处即结束。、
;@params:
;    eax:字符串段起始偏移位置。
;@return:
;    eax：保存了编译后的起始线性地址
;使用方式：远程调用
;注意事项：无

compileCommandLine:
    push ebx
    push ecx
    push edx
    push edi
    push esi

    mov esi,eax
    call seperate_word_by_space  
    cmp ecx,0x00
        je .exit

    ;此处应该开始获取表格内容,也就是get_word_location
    call get_command_word_location
    xor eax,eax
    cmp edi,0x00
        je .exit

    ;接下来应该是编译命令，并送到相关的命令运行器运行了。
    xor eax,eax
    mov word ax,[cs:edi]    ;获取操作数
    
    call generate_command_line_binary_data
    xor eax,eax
    cmp edi,0x00
        je .exit
    
    mov eax,[cs:program_linear_address]
    add eax,compile_buffer_start

    .exit:
        pop esi
        pop edi
        pop edx
        pop ecx
        pop ebx
        retf

;-------------------------------------------------------
;此函数用于编译一段程序文件。
;@params:
;    eax:字符串起始偏移位置。
;@return:
;    eax:保存了编译后的起始线性地址。
;使用方式：远程调用
;注意事项：无
compileSourceCode:
    push ebx
    push ecx
    push edx
    push esi 
    push edi
    
    mov esi,eax
    call syntax_check

    cmp edi,STRING_TYPE_END
        jne .exit_error
    ;词法和语法检查无误后，开始进入程序生成阶段。
    call clear_compile_buffer  ;清空编译缓存
    call set_generate_message ;重新复位行号，设置起始数据位置。
    xor eax,eax    ;如果开始就是空的，那么返回结果肯定也是0、

    .start_generate:
        call seperate_word_with_type
        cmp edi,STRING_TYPE_END
            je .compile_finished     ;程序为空，自然就不能编译通过啦。
        cmp edi,STRING_TYPE_LINE_END
            jne .continue_generate
        add esi,ecx
        call update_line_number
        jmp .start_generate

    .continue_generate:
        cmp edi,STRING_TYPE_LABEL    ;如果是标号，则可以指向下一行数据了，因为词法和语法检查阶段已经生成了相关的标号和地址。
            je .generate_next
        
        call get_command_word_location ;不是标号开头的情况，就只能是命令行开头的情况了。词法分析和语法分析也做了。
        cmp edi,0x00 
            je .exit_error
        xor eax,eax  
        mov word ax,[cs:edi]    ;获取命令操作数
        call add_code_data_to_compile_buffer   ;先将操作数添加至编译缓存中。
        call generate_source_code_data
        cmp eax,0x00 
            je .exit

    .generate_next:   ;指向下一行
        add esi,ecx 
        jmp .start_generate
    
    .compile_finished:
        mov dword eax,[cs:program_linear_address]
        add eax,compile_buffer

    .exit:
        ;更新编译缓存长度
        mov dword edi,[cs:program_linear_address]
        mov dword ebx,[ds:edi+argument_address]
        mov dword [ds:edi+compile_buffer_pointer],ebx
        ;call show_compile_buffer
        ;call show_args_table

        pop edi 
        pop esi 
        pop edx 
        pop ecx
        pop ebx
        retf

    .exit_error:
        xor eax,eax
        ;push esi 
        ;mov esi,string_message_unknown_command
        ;call show_settings_message
        ;pop esi 
        jmp .exit

;--------------------------------------------------------
;此函数用于根据命令操作数生成相应的二进制代码。
;@params:
;    eax:
;    ecx:
;    esi:
;    ds:
;@return:
;    esi:
;    ecx:
;    ds:
;    eax:返回编译结果，如果为0则表示编译出错了。
;使用方式:近程调用
;注意事项：编译完成后不需要再手动添加下一个字符串指向。
generate_source_code_data:
    push ebx
    push edx 
    push edi 

    cmp eax,0x01 ;prints 命令
        je generate_one_input_params_length_1   ;不限类型的单个参数的命令
    cmp eax,0x07 ;stayPrints 命令
        je generate_one_input_params_length_1   ;不限类型的单个参数的命令
    cmp eax,0x0c
        je generate_one_input_params_length_4

    cmp eax,0x0d ;copy命令
        je generate_two_input_params_length_0   ;两个输入参数的命令。

    cmp eax,0x0e ;inc 自增指令
        je generate_one_input_params_length_4   ;只允许长度为4的数据类型
    cmp eax,0x0f  ;add
        je generate_two_input_params_length_4
    cmp eax,0x10  ;dec
        je generate_one_input_params_length_4 
    cmp eax,0x11  ;sub
        je generate_two_input_params_length_4
    cmp eax,0x32  ;jump
        je generate_one_input_params_length_0    ;只允许长度为0的地址标号类型。
    cmp eax,0x33  ;repeat
        je generate_two_input_params_length_0_4    ;只允许长度为0的标号类型和数字类型。 
    cmp eax,0x13  ;sleep
        je generate_one_intput_param_length_4_constant
    
    cmp eax,0x68  ;getTimeString
        je generate_one_output_params_length_64 
    cmp eax,0x69  ;getDateString
        je generate_one_output_params_length_64 

    .else:
        call show_line_message
        push esi 
        mov esi,string_message_unknown_command
        call show_settings_message
        pop esi 
        xor eax,eax 
        pop edi 
        pop edx 
        pop ebx 
        ret 
;--------------------编译单个参数的命令,示例：prints------------------------------
    generate_one_input_params_length_1:
        add esi,ecx 
        call seperate_word_with_type
        mov ebx,edi 

        call get_label_from_args_table
        cmp edx,0x00
            je .arg_not_defined   ;数据长度为0说明是标号类型，直接提示参数不存在。
        
        cmp edi,0x00 
            jne .continue_arg_existed   ;参数已经存在了，就直接添加到数据表中即可。
        .arg_not_defined:
            ;其余的是参数不存在的情况。
            cmp ebx,STRING_TYPE_NORMAL
                je common_exit_arg_not_defined   ;如果是常规类型，则提示参数不存在。
            cmp ebx,STRING_TYPE_STRING
                je .constant_type_string

            mov edx,0x0c          ;数字类型的数据长度
            jmp .add_constant_type
        .constant_type_string:     ;常量类型为字符串
            mov edx,72
        .add_constant_type:
            call add_constant_type_to_arg_table
            mov dword eax,[cs:argument_address]
            call update_data_segment_length
        .continue_arg_existed:    ;添加该变量的数据地址至程序段中。
            call add_code_data_to_compile_buffer   ;eax表示地址
            jmp compile_exit 

;--------------------编译两个参数的命令,示例:copy------------------------------
    generate_two_input_params_length_0:
        add esi,ecx
        push esi   

        call seperate_word_with_type   
        add esi,ecx

        call seperate_word_with_type    ;获得第二个参数的类型
        mov ebx,edi 

        call get_label_from_args_table
        cmp edi,0x00 
            je .arg2_not_defined        ;第二个参数不存在的情况，直接新建。
        cmp edx,0x00
            je common_exit_arg2_wrong_type    ;如果存在，那么edx数据长度又为0,说明这是一个标号类型，直接提示不合法。
        
        ;其他情况就是arg2存在的情况了。
        jmp .continue_arg2_existed

        .arg2_not_defined:
            cmp ebx,STRING_TYPE_NORMAL
                je common_exit_arg2_not_defined   ;如果是常规类型，则提示参数不存在。
            cmp ebx,STRING_TYPE_STRING
                je .constant_type_string

            mov edx,0x04          ;数字类型的数据长度
            jmp .add_constant_type
        
        .constant_type_string:     ;常量类型为字符串
            mov edx,64
        
        .add_constant_type:
            call add_constant_type_to_arg_table
            mov dword eax,[cs:argument_address]
            call update_data_segment_length
            
        .continue_arg2_existed:    ;添加该变量的数据地址至程序段中。            
            mov ebx,edx   ;先保存参数2的数据长度。
            call add_code_data_to_compile_buffer

            ;此时edx中保存了参数2的长度，eax保存了参数2的数据地址，开始处理参数1
            pop esi 
            call seperate_word_with_type    ;得到第一个参数名称

            cmp edi,STRING_TYPE_NORMAL   ;参数1只能是标准的参数类型。
                jne compile_exit_argument_wrong_type
            
            call get_label_from_args_table
            cmp edi,0x00 
                je .create_new_arg1
            cmp edx,0x00     ;后面跟了标号类型，直接表示错误
                je compile_exit_argument_wrong_type

            ;如果参数1存在，且参数2也存在，则需要对比两者的数据长度是否一致，只有数据长度一致，才能够赋值。
            cmp edx,ebx 
                jne compile_exit_argument_wrong_type

            call add_code_data_to_compile_buffer   ;写入参数1的数据地址。
            add esi,ecx 
            call seperate_word_with_type
            jmp compile_exit

        .create_new_arg1:
            mov edx,ebx
            call add_label_to_args_table
            mov dword eax,[cs:argument_address]
            call update_data_segment_length    ;更新数据长度edx
            call add_code_data_to_compile_buffer

            add esi,ecx 
            call seperate_word_with_type
            jmp compile_exit   

;--------------------编译单个参数的命令，只允许数字类型-------------------------
    generate_one_input_params_length_4:
        add esi,ecx 
        call seperate_word_with_type
        cmp edi,STRING_TYPE_NORMAL
           jne compile_exit_argument_wrong_type
        call get_label_from_args_table
        cmp edx,0x00
            je common_exit_arg_not_defined
        cmp edx,0x04 ;判断数据长度是否为4，如果不为4,表示参数长度错误
            jne compile_exit_argument_wrong_type
        call add_code_data_to_compile_buffer
        jmp compile_exit

;--------------------编译两个参数的命令，只允许两个都是数字类型,而且要求都存在-------------------
    generate_two_input_params_length_4:
        add esi,ecx 
        call seperate_word_with_type
        cmp edi,STRING_TYPE_NORMAL
           jne compile_exit_argument_wrong_type
        call get_label_from_args_table
        cmp edx,0x00
            je common_exit_arg_not_defined
        cmp edx,0x04 ;判断数据长度是否为4，如果不为4,表示参数长度错误
            jne compile_exit_argument_wrong_type
        call add_code_data_to_compile_buffer
        ;开始处理第二个参数
        add esi,ecx 
        call seperate_word_with_type
        mov ebx,edi 
        call get_label_from_args_table
        cmp edx,0x04 
           je .arg2_existed 
        ;cmp ebx,STRING_TYPE_NORMAL
            ;je compile_exit_argument_wrong_type
        cmp ebx,STRING_TYPE_DECIMAL
            jne compile_exit_argument_wrong_type
        
        call add_constant_type_to_arg_table
        mov edx,0x0004
        mov dword eax,[cs:argument_address]
        call update_data_segment_length
        .arg2_existed:   ;参数2存在的情况，直接添加地址即可
            call add_code_data_to_compile_buffer
            jmp compile_exit


;--------------------编译一个参数的命令，只允许标号类型,示例:jump--------------------------
    generate_one_input_params_length_0:
        add esi,ecx 
        call seperate_word_with_type
        cmp edi,STRING_TYPE_NORMAL
            jne compile_exit_argument_wrong_type
        call get_label_from_args_table
        cmp edi,0x00
            je common_exit_arg_not_defined
        cmp edx,0x00 
            jne compile_exit_argument_wrong_type
        call add_code_data_to_compile_buffer
        jmp compile_exit

;--------------------编译两个参数的命令，只允许标号类型和数字类型,示例:repeat--------------------------
    generate_two_input_params_length_0_4:
        add esi,ecx 
        call seperate_word_with_type
        cmp edi,STRING_TYPE_NORMAL
            jne compile_exit_argument_wrong_type
        call get_label_from_args_table
        cmp edi,0x00
            je common_exit_arg_not_defined
        cmp edx,0x00 
            jne compile_exit_argument_wrong_type
        call add_code_data_to_compile_buffer
        
        add esi,ecx 
        call seperate_word_with_type
        mov ebx,edi 
        call get_label_from_args_table
        cmp edx,0x04 
           je .arg2_existed 
        ;cmp ebx,STRING_TYPE_NORMAL
            ;je common_exit_arg_not_defined
        cmp ebx,STRING_TYPE_DECIMAL
            jne compile_exit_argument_wrong_type
        
        call add_constant_type_to_arg_table
        mov edx,0x0004
        mov dword eax,[cs:argument_address]
        call update_data_segment_length

        .arg2_existed:   ;参数2存在的情况，直接添加地址即可
            call add_code_data_to_compile_buffer
            jmp compile_exit

;--------------------编译单个参数的命令，只允许字符串类型，示例：getTimeString-------------------------
    generate_one_output_params_length_64:
        add esi,ecx 
        call seperate_word_with_type
        cmp edi,STRING_TYPE_NORMAL
           jne compile_exit_argument_wrong_type
        call get_label_from_args_table
        cmp edi,0x00 
            je .arg_not_defind 
        cmp edx,0x00
            je common_exit_arg_not_defined
        cmp edx,64 ;判断数据长度是否为64，如果不为4,表示参数长度错误
            jne compile_exit_argument_wrong_type
        call add_code_data_to_compile_buffer
        jmp compile_exit

        .arg_not_defind:     ;参数未定义的情况，就定义参数类型
            mov edx,64
            call add_label_to_args_table
            mov dword eax,[cs:argument_address]
            call update_data_segment_length    ;更新数据长度edx
            call add_code_data_to_compile_buffer  ;更新代码段长度
            jmp compile_exit

;--------------------编译单个参数的命令，只允许数字类型，示例：sleep--------------------
    generate_one_intput_param_length_4_constant:
        add esi,ecx 
        call seperate_word_with_type
        mov ebx,edi 
        call get_label_from_args_table
        cmp edx,0x04 
           je .arg_existed 
        cmp ebx,STRING_TYPE_DECIMAL
           jne compile_exit_argument_wrong_type
        
        call add_constant_type_to_arg_table
        mov edx,0x0004
        mov dword eax,[cs:argument_address]
        call update_data_segment_length

        .arg_existed:   ;参数2存在的情况，直接添加地址即可
            call add_code_data_to_compile_buffer
            jmp compile_exit

;-------------公共错误提示区-------------------------
    common_exit_arg_not_defined:
        call show_line_message
        push esi
          mov esi,message_argument_not_defined
          call show_settings_message
        pop esi
        xor eax,eax
        jmp compile_exit

    common_exit_arg2_not_defined:
        call show_line_message
        push esi
          mov esi,message_argument_not_defined
          call show_settings_message
        pop esi
        pop esi 
        xor eax,eax
        jmp compile_exit

    common_exit_data_length_wrong:
        xor eax,eax 
        push esi
          mov esi,illegle_argument_length_wrong
          call show_settings_message
        pop esi
        jmp compile_exit

    compile_exit_wrong:
        call show_line_message
        xor eax,eax
        push esi
          mov esi,message_argument_not_defined
          call show_settings_message
        pop esi
        jmp compile_exit

    exit_wrong_label_not_exists:
        call show_line_message
        push esi
          mov esi,message_label_not_exists
          call show_settings_message
        pop esi
        xor eax,eax
        jmp compile_exit
    
    common_exit_arg2_wrong_type:
        pop esi 
    compile_exit_argument_wrong_type:
        xor eax,eax
        call show_line_message
        push esi
          mov esi,illegle_argument_wrong_type
          call show_settings_message
        pop esi
 
    compile_exit:
        pop edi
        pop edx
        pop ebx
        ret

compile_inc_bin:
compile_jump_bin:
compile_repeat_bin:
compile_copy_bin:

;--------------------------------------------------------
;此函数用于编译阶段向数据表中添加一个常量类型。
;@params:
;    ebx:需要添加的常量类型,会自动设置为4和字符串长度。
;    esi:
;    ecx:
;    ds:
;@return:
;    edi:0x00表示添加失败了。
;使用方式:近程调用
;注意事项:仅添加常量类型，数据段和程序段长度需要手动更新。
add_constant_type_to_arg_table:
    push eax 
    push ebx 
    push ecx 
    push esi 

    call add_label_to_args_table   ;只添加数据地址和数据长度，不添加数据内容。

    mov dword edi,[cs:program_linear_address]
    add edi,compile_buffer
    mov dword eax,[cs:argument_address]
    add eax,0x04
    
    cmp ebx,STRING_TYPE_NORMAL
        je .exit_error   ;如果是常规类型，则提示参数不存在。
    cmp ebx,STRING_TYPE_STRING
        je .constant_type_string
    
    .constant_type_number:
        mov dword [ds:edi+eax],0x04   ;数字的数据长度为4字节
        add eax,0x04   ;指向内容位置。

        push edi
        call convert_string_to_dec
        cmp edi,0x00 
            je .exit_error
        pop edi
        mov dword [ds:edi+eax],ebx 
        jmp .exit

    .constant_type_string:
        sub ecx,0x02 
        mov dword [ds:edi+eax],64   ;写入数据长度
        add eax,0x04 
    .copy_string:   ;写入字符串内容。
        inc esi
        mov byte bl,[ds:esi]
        mov byte [ds:edi+eax],bl  
        inc eax 
        loop .copy_string

    .exit:
        pop esi 
        pop ecx 
        pop ebx 
        pop eax 
        ret 

    .exit_error:
        pop edi 
        xor edi,edi 
        jmp .exit 

;--------------------------------------------------------
;此函数用于转换一个字符串数字类型至16进制格式
;@params:
;    esi:
;    ecx:
;    ds:
;@return:
;    ebx:返回转换后的结果
;    edi:表示数据是否有效，0x00表示数据无效，转换失败了。
;使用方式：近程调用
;注意事项：暂无
convert_string_to_dec:
    push eax 
    push edx 
    push ecx
    push esi

    mov edi,ecx  
    xor eax,eax
    xor edx,edx
    xor ebx,ebx

    .start:
        mov byte bl,[ds:esi]
        cmp ebx,0x2f   ;大于30，可以继续
            jg .continue
        ;小于字符0的情况，直接退出
        jmp .finish 
    .continue:
        cmp ebx,0x39  ;大于9的情况,不是可转换字符
            jg .finish

        sub ebx,0x30    ;这就是在0-9之间的情况了
        add eax,ebx

        cmp ecx,0x01
            je .convert_finished_normally
        mov ebx,0x0a
        mul ebx
        inc esi
        loop .start

    .convert_finished_normally:
        mov ebx,eax       ;bx返回数据长度

    .exit:
        pop esi
        pop ecx
        pop edx 
        pop eax 
        ret


    .finish:
        xor ebx,ebx
        xor edi,edi 
        jmp .exit
;--------------------------------------------------------
;此函数用于添加指令数据到编译缓存中。
;@params:
;    eax；保存了需要添加的指令数据
;@return:
;    NONE
;使用方式：近程调用
;注意事项：暂无
add_code_data_to_compile_buffer:
    push ebx
    push edi 
    mov dword edi,[cs:program_linear_address]
    mov dword ebx,[cs:compile_buffer_pointer]
    mov dword [ds:edi+ebx+compile_buffer],eax 
    add ebx,0x04
    mov dword [ds:edi+compile_buffer_pointer],ebx
    pop edi 
    pop ebx 
    ret

;--------------------------------------------------------
;此函数用于添加指令数据到编译缓存中。
;@params:
;    eax；保存了需要添加的指令数据
;@return:
;    NONE
;使用方式：近程调用
;注意事项：暂无
clear_compile_buffer:
    push ecx
    push edi

    mov dword edi,[cs:program_linear_address]
    add edi,compile_buffer
    mov dword [ds:edi],0x04   ;重置指针
    mov dword ecx,511   ;2044个字节的编译缓存大
    .clear:
        add edi,0x04
        mov dword [ds:edi],0x0000
        loop .clear
    .exit:
        pop edi 
        pop ecx 
        ret
;--------------------------------------------------------
;此函数用于编译字符串的语法检查，并生成相应的词汇表，便于进行最终文件的生成。
;@params:
;    eax:文本文档指向的线性地址
;@return:
;    edi:编译结果，edi不为0则表示编译正常结束了。
;使用方式:近程调用
;注意事项：暂无

syntax_check:
    ;关机指令
    ;mov dx,0x805
    ;mov al,0x3c 
    ;out dx,al

    push eax
    push ebx 
    push ecx
    push edx 
    push esi 

    ;指向编译词汇表
    mov esi,eax
    mov edi,[cs:program_linear_address]
    add edi,arguments_table_start   ;指向编译参数表
    call clear_arg_table 
    call clear_compile_message
    mov dword edi,[ds:esi]
    cmp edi,0x00 
        je .exit_empty_content
    .check_line_start:    ;从每一行的行首开始检查
        call seperate_word_with_type
        ;jmp .debug_string

        cmp edi,STRING_TYPE_END    ;正常结束
            je .exit 
        cmp edi,STRING_TYPE_NORMAL
            je .command_start    ;每一行只能是标号开始，或者命令开始。否则都不合法。
        cmp edi,STRING_TYPE_LABEL
            je .label_start
        cmp edi,STRING_TYPE_LINE_END
            jne .exit_illegal_line_start

        call update_line_number    ;更新行号
        jmp .check_line_start
    
    ;开头是标号的情况。
    .label_start:
        dec ecx ;减去一个长度，也就是冒号。
        call get_label_from_args_table
        cmp edi,0x00 
            jne .exit_label_redefined
        xor edx,edx 
        call add_label_to_args_table   ;将label添加到参数表中。
        inc ecx
        jmp .check_lines_ending
    ;开头是命令的情况。
    .command_start:
        call get_command_word_location  
        cmp edi,0x00
            je .exit_illegal_line_start
        ;获得参数的个数
        xor eax,eax
        mov byte al,[cs:edi+0x04]  ;获得参数命令个数
        call update_code_segment_length

        cmp al,0x00 
            je .match_zero_params
        cmp al,0x01 
            je .match_one_params
        cmp al,0x02 
            je .match_two_params

        jmp .exit_unknown_command  ;其他情况应该提示未知命令。

    ;命令是两个参数的情况，必须保证两个参数都是符合规则的。
    .match_two_params:    ;两个参数的情况,第一个参数可以是不确定的，但是要由第二个参数决定大小
        xor ebx,ebx 
        mov word bx,[cs:edi+0x02]   ;得到命令数据长度，0表示只能接标号类型。1表示不限制数据输入，则不用创建数据大小，

        ;不管是什么类型的命令，后续只能跟常规类型、字符串类型、数字类型，其余的都会报错。
        add esi,ecx 
        call seperate_word_with_type

        cmp edi,STRING_TYPE_END ;正常字符串结束了
            je .exit_command_missing_argument
        cmp edi,STRING_TYPE_LINE_END
            je .exit_command_missing_argument
        cmp edi,STRING_TYPE_UNKNOWN
            je .exit_illegal_argment    ;其他类型则显示参数错误。
        cmp edi,STRING_TYPE_SYMBOL
            je .exit_illegal_argment
        cmp edi,STRING_TYPE_LABEL
            je .exit_illegal_argment

        ;判断后面的字符串不能为命令了。
        cmp edi,STRING_TYPE_NORMAL
            jne .string_or_number_type

        call get_command_word_location
        cmp edi,0x00 
            jne .exit_command_followed_command  ;命令后跟着命令，提示保留字。
        
        .string_or_number_type:

    ;命令带一个参数的情况    
    .match_one_params:    ;一个参数的情况
        xor ebx,ebx 
        mov word bx,[cs:edi+0x02]   ;得到命令数据长度，0表示只能接标号类型。1表示不限制数据输入，则不用创建数据大小，

        ;不管是什么类型的命令，后续只能跟常规类型、字符串类型、数字类型，其余的都会报错。
        add esi,ecx 
        call seperate_word_with_type

        cmp edi,STRING_TYPE_END ;正常字符串结束了
            je .exit_command_missing_argument
        cmp edi,STRING_TYPE_LINE_END
            je .exit_command_missing_argument
        cmp edi,STRING_TYPE_UNKNOWN
            je .exit_illegal_argment    ;其他类型则显示参数错误。
        cmp edi,STRING_TYPE_SYMBOL
            je .exit_illegal_argment
        cmp edi,STRING_TYPE_LABEL
            je .exit_illegal_argment

        ;判断后面的字符串不能为命令了。
        cmp edi,STRING_TYPE_NORMAL
            jne .string_or_number_type2

        call get_command_word_location
        cmp edi,0x00 
            jne .exit_command_followed_command  ;命令后跟着命令，提示保留字。
        
        .string_or_number_type2:

    .match_zero_params:    ;命令开头且没有参数的情况,只要更新代码段即可。
        jmp .check_lines_ending

    .check_lines_ending:      ;一行应该是结束的，如果不是结束，则提示非法结束。
        add esi,ecx 
        call seperate_word_with_type
        cmp edi,0x01    ;正常结束
            je .exit 
        cmp edi,0x02    ;行末结束,开始下一行判断。
            jne .exit_illegal_extra_letters_ending
        call update_line_number
        jmp .check_line_start

    .exit:  
        pop esi 
        pop edx 
        pop ecx 
        pop ebx 
        pop eax 
        ret 

    .exit_wrong_label: 
        call show_line_message 
        push esi
        mov esi,string_message_wrong_label_end
        call show_settings_message
        pop esi 
        jmp .exit 

    .exit_illegal_line_start:     ;必须以命令或者标号作为行起始
        call show_line_message 
        push esi
        mov esi,string_message_illegal_line_start
        call show_settings_message
        pop esi 
        jmp .exit 

    .exit_label_redefined:  
        call show_line_message
        push esi
        mov esi,string_message_label_redefined
        call show_settings_message
        pop esi 
        jmp .exit
    
    .exit_command_missing_argument:      ;参数丢失
        call show_line_message
        push esi
        mov esi,string_message_command_missing_parameter
        call show_settings_message
        pop esi 
        jmp .exit
    
    .exit_illegal_name:
        call show_line_message
        push esi
        mov esi,string_message_illegal_name
        call show_settings_message
        pop esi 
        jmp .exit
    
    .exit_illegal_argment2_not_exists:
        call show_line_message
        push esi
        mov esi,string_message_illegal_argument2_not_exists
        call show_settings_message
        pop esi 
        jmp .exit

    .exit_illegal_argment:
        call show_line_message
        push esi
        mov esi,string_message_illegal_argument
        call show_settings_message
        pop esi 
        jmp .exit

    .exit_illegal_extra_letters_ending:
        call show_line_message
        push esi
        mov esi,string_message_illegal_extra_letters_ending
        call show_settings_message
        pop esi 
        jmp .exit
    
    .exit_unknown_command:
        call show_line_message
        push esi
        mov esi,string_message_unknown_command
        call show_settings_message
        pop esi 
        jmp .exit

    .exit_command_followed_command:
        call show_line_message
        push esi
        mov esi,string_message_command_can_not_be_argument
        call show_settings_message
        pop esi 
        jmp .exit
        
    .exit_empty_content:
        mov edi,0x10 
        jmp .exit 

    .debug_string:
        push eax 
        push edi 
        mov eax,edi 
        mov edi,0x03
        call far [cs:common_service_entry]
        mov edi,0x01
        call far [cs:common_service_entry]
        mov eax,0x0d 
        mov edi,0x02
        call far [cs:common_service_entry]
        pop edi
        pop eax 
        cmp edi,0x00
            je .exit     ;非正常结束
        cmp edi,0x01     ;正常结束
            je .exit
        add esi,ecx 
        jmp .check_line_start

;-------------------------------------------
;此函数用于打印编译错误的行号以及字符串信息。

show_line_message:
    push eax 
    push edi
    push esi
    
    mov eax,0x0d 
    mov edi,0x02 
    call far [cs:common_service_entry]

    mov edi,0x01 
    call far [cs:common_service_entry]

    mov esi,string_message_line
    call show_settings_message

    mov dword eax,[cs:line_number]
    mov edi,0x03 
    call far [cs:common_service_entry]

    mov esi,string_message_line_end
    call show_settings_message

    pop esi 
    pop edi 
    pop eax
    ret 

;此函数用于清空参数表
clear_arg_table:
    push ecx
    push edi 
    mov edi,[cs:program_linear_address]
    add edi,arguments_table   ;指向编译参数表
    mov dword [ds:edi],arguments_table_start  ;设置起始指针
    mov ecx,511  ;清除剩下的2044个字节
    .clear:
        add edi,0x04
        mov dword [ds:edi],0x0000_0000
        loop .clear 
    pop edi 
    pop ecx
    ret

;此函数用于清空编译信息，如行号、数据段大小、代码段大小
clear_compile_message:
    push edi
    mov edi,[cs:program_linear_address]
    add edi,label_address
    mov dword [ds:edi],0x0004    ;清除代码段大小
    add edi,0x04
    mov dword [ds:edi],0x0000    ;清除数据段大小
    add edi,0x04
    mov dword [ds:edi],0x0001    ;清除行号
    pop edi 
    ret 

;此函数用于设置起始的代码生成信息，包括重置数据段起始位置，以及起始行号。注意，数据段和代码段之间必须留足16个字节。用于后续扩展。
set_generate_message:
    push eax 
    push edi
    mov edi,[cs:program_linear_address]
    add edi,label_address
    mov dword eax,[ds:edi]
    add eax,0x10   ;保留的字节
    add edi,0x04
    mov dword [ds:edi],eax    ;清除数据段大小
    add edi,0x04
    mov dword [ds:edi],0x0001    ;清除行号
    pop edi 
    pop eax 
    ret

;--------------------------------------------------
;此函数用于调试过程中显示编译缓存中的内容。
;@params:NONE
;@return:NONE
;使用方式：近程调用
;注意事项：暂无
show_compile_buffer:
    push eax 
    push ebx 
    push ecx
    push edi

    mov dword ebx,[cs:program_linear_address]
    add ebx,compile_buffer
    mov ecx,128
    mov edi,0x03 
    xor eax,eax 
    .show:
        test ecx,0x0003
           jnz .continue 
        mov byte al,0x20 
        mov edi,0x02 
        call far [cs:common_service_entry]

        .continue:
        mov byte al,[ds:ebx]
        mov edi,0x03 
        call far [cs:common_service_entry]
        inc ebx 
        loop .show
    .exit:
        pop edi 
        pop ecx 
        pop ebx 
        pop eax 
        ret

show_args_table:
    push eax 
    push ebx 
    push ecx
    push edi

    mov dword ebx,[cs:program_linear_address]
    add ebx,arguments_table
    mov ecx,128
    mov edi,0x03 
    xor eax,eax 
    .show:
        test ecx,0x0003
           jnz .continue 
        mov byte al,0x20 
        mov edi,0x02 
        call far [cs:common_service_entry]

        .continue:
        mov byte al,[ds:ebx]
        mov edi,0x03 
        call far [cs:common_service_entry]
        inc ebx 
        loop .show
    .exit:
        pop edi 
        pop ecx 
        pop ebx 
        pop eax 
        ret
;-----------------------------------------------
;此函数用于更新代码段长度
;@params:
;    eax:参数个数
;@return:
;    NONE
;使用方式：近程调用
;注意事项：在每次检查完指令后都需要更新一下代码段长度
update_code_segment_length:
    push eax
    push ecx 
    push edi
    mov edi,[cs:program_linear_address]
    add edi,label_address
    mov ecx,eax
    inc ecx 
    mov dword eax,[ds:edi] 
    .count_code_length:
        add eax,0x04
        loop .count_code_length
    mov dword [ds:edi],eax 
    pop edi 
    pop ecx 
    pop eax 
    ret

;此函数用于更新数据段长度
;@params:
;    edx:数据长度
;@return:
;    NONE
;使用方式：近程调用
;注意事项：当遇到参数表中已存在的数据段时，不需要重复更新.参数的最大长度为65536个字节
update_data_segment_length:
    push eax 
    push edi
    mov edi,[cs:program_linear_address]
    add edi,argument_address
    mov dword eax,[ds:edi]
    add eax,edx
    add eax,0x08  
    mov dword [ds:edi],eax 
    pop edi 
    pop eax 
    ret

;此函数用于更新打印行号
update_line_number:
    push eax 
    push edi
    mov edi,[cs:program_linear_address]
    add edi,line_number
    mov dword eax,[ds:edi]
    inc eax 
    mov dword [ds:edi],eax 
    pop edi 
    pop eax 
    ret 

;-----------------------------------------------
;此函数用于增加一个标号至参数表中.
;@params:
;    esi:
;    ecx:
;    edx:    保存需要添加的变量数据长度
;    ds:
;@return:
;    NONE
;使用方式：近程调用
;注意事项：使用前需要先更新代码段或数据段地址。
add_label_to_args_table:
    push eax 
    push ebx 
    push ecx 
    push esi 
    push edi 

    mov dword edi,[cs:program_linear_address] 
    mov dword ebx,[cs:arguments_table_pointer];得到参数表的绝对地址
    cmp edx,0x00
        je .add_label   ;如果数据长度为0，说明这是一个标号，或者是一条指令，那么自然是从代码段中获得地址
    mov dword eax,[cs:argument_address]
    .continue_add:
        mov dword [ds:edi+ebx],eax ;填入数据地址
        add ebx,0x04
        mov word [ds:edi+ebx],dx    ;填入数据长度
        add ebx,0x02 
        mov byte [ds:edi+ebx],cl    ;填入名称长度
        inc ebx
        .copy_name:
            mov byte al,[ds:esi]
            mov byte [ds:edi+ebx],al 
            inc esi 
            inc ebx 
            loop .copy_name
    ;回填参数表指针。
    mov dword [ds:edi+arguments_table_pointer],ebx 
    pop edi 
    pop esi 
    pop ecx 
    pop ebx 
    pop eax 
    ret

    .add_label:   ;添加的是标号类型
        mov dword eax,[cs:label_address]
        jmp .continue_add

;-----------------------------------------------
;此函数用于从参数命令表中获得个标号或者参数名称的信息
;@params:
;    esi:
;    ecx:
;    ds:
;@return:
;    eax:返回参数地址
;    edx:返回数据长度
;    edi:参数位置，指向参数地址位置
;使用方式:近程调用
;注意事项:当没有找到参数地址时，返回数据长度和地址长度均为0
get_label_from_args_table:
    push ebx
    push ecx

    mov dword edx,[cs:arguments_table_pointer] ;获得参数表长度

    xor ebx,ebx
    xor eax,eax
    mov byte al,[ds:esi]
    shl ax,0x08
    add eax,ecx
    mov edi,arguments_table_start
    add edi,0x06   ;指向名称长度

    .start_match:
        mov word bx,[cs:edi]
        cmp bx,ax           ;只有长度和第一个字节相符，才会进行字符串的匹配。
            je .match_content

    .match_next:
        ;不匹配的情况直接指向下一个
        and ebx,0x0000_00ff ;取得长度值
        add edi,ebx
        add edi,0x07   ;指向下一个字节指令,因为指向的是长度，所以还需要再加上字节长度本身。

        cmp edi,edx
            jng .start_match

        xor edi,edi  ;已经超出了表格范围，直接未找到
        xor eax,eax 
        xor edx,edx 

    .exit:
        pop ecx
        pop ebx
        ret 

    .match_content:
        push ebx 
        push edx 
        push esi
        push edi
        inc edi

    .match_content_start:
        mov byte dl,[ds:esi]
        mov byte bl,[cs:edi]
        cmp bl,dl           
            jne .match_content_end   ;不匹配的情况直接匹配结束
        inc edi
        inc esi
        loop .match_content_start

    .match_content_end: 
        pop edi
        pop esi
        pop edx 
        pop ebx 

        cmp ecx,0x00       ;此时ax已经保存了cx字符串的值。该字符串最大长度为255个字节。
            je .found_label
        ;未能匹配到的情况，需要恢复ecx的长度
        mov ecx,eax 
        and ecx,0xff    ;一个字节的长度
        jmp .match_next

    .found_label:       ;找到了该名称的情况。
        sub edi,0x02    ;指向参数的数据长度
        xor edx,edx 
        mov word dx,[cs:edi]
        sub edi,0x04
        mov dword eax,[cs:edi]
        jmp .exit 

;-----------------------------------------------
;此函数用于根据命令类型生成对应的可执行代码
;@params:
;   eax:保存了需要编译的命令
;@return:
;   eax:保存了编译后的起始线性地址
;使用方式：近程调用
;注意事项：暂无
generate_command_line_binary_data:
    xor edi,edi
    cmp eax,0x01
        je generate_one_string_params   
    cmp eax,0x05
        je generate_no_params
    
    cmp eax,0x66
        je generate_no_params

    cmp eax,0x67
        je generate_no_params

    cmp eax,0x70
        je generate_one_string_params

    cmp eax,0x71
        je generate_no_params
    cmp eax,0x72
        je generate_one_string_params
    cmp eax,0x75
        je generate_no_params
    cmp eax,0x76
        je generate_one_string_params
    cmp eax,0x77
        je generate_one_string_params
    cmp eax,0x78
        je generate_one_string_params
    
    cmp eax,0xc8
        je generate_no_params
        
    cmp eax,0x12c
        je generate_no_params
    cmp eax,0x12d
        je generate_one_string_params
    cmp eax,0x12e
        je generate_one_string_params
    cmp eax,303
        je generate_no_params
    cmp eax,304
        je generate_no_params
    cmp eax,305
        je generate_one_string_params
    cmp eax,306
        je generate_one_string_params
generate_exit:
    ret 

;此函数用于编译命令行的直接字符串类型的命令
generate_one_string_params:

    add esi,ecx
    call seperate_word_by_space
    cmp cx,0x00
        je generate_exit
    ;否则写入数据
    mov ebx,[cs:program_linear_address]
    add ebx,compile_buffer_start    ;指向起始编译位置
    mov word [ds:ebx],ax    ;填入操作数
    add ebx,0x02
    mov word [ds:ebx],cx    ;填入数据长度
    add ebx,0x02
    .copy_data:
        mov byte al,[ds:esi]
        mov byte [ds:ebx],al
        inc esi
        inc ebx
        loop .copy_data
    mov dword [ds:ebx],0x00
    add esi,ecx
    mov edi,0x01
    jmp generate_exit

generate_no_params:

    ;否则写入数据
    mov ebx,[cs:program_linear_address]
    add ebx,compile_buffer_start    ;指向起始编译位置

    mov word [ds:ebx],ax    ;填入操作数
    add ebx,0x02
    mov word [ds:ebx],0x00    ;填入数据长度
    add ebx,0x02

    add esi,ecx
    mov edi,0x01
    jmp generate_exit

;此函数用于在命令表中匹配一个字符串，并给出位置。
;@params:
;    ds:需要寻找的字符串段
;    esi:字符串的起始偏移位置
;    ecx:字符串长度
;@return:
;    edi:保存了偏移位置，指向命令的操作数。0表示未找到
;使用方式：近程调用
;注意事项：无

get_command_word_location:
    push eax
    push ebx
    push ecx
    push edx

    xor edx,edx
    xor eax,eax
    mov byte al,[ds:esi]
    shl ax,0x08
    add eax,ecx
    mov edi,command_table

    .start_match:
        mov word dx,[cs:edi]
        cmp dx,ax           ;只有长度和第一个字节相符，才会进行字符串的匹配。
            je .match_content

    .match_next:
        ;不匹配的情况直接指向下一个
        and edx,0x0000_00ff ;取得长度值
        add edi,edx
        
        add edi,0x06   ;指向下一个字节指令。
        cmp edi,command_table_end
            jng .start_match

        xor edi,edi  ;已经超出了表格范围，直接未找到

    .exit:
        pop edx
        pop ecx
        pop ebx
        pop eax
        ret 

    .match_content:
        push ecx
        push edx
        push edi
        push esi
        inc edi

    .match_content_start:
        mov byte bl,[ds:esi]
        mov byte dl,[cs:edi]
        cmp bl,dl           ;不匹配的情况应该直接指向下一个。
            jne .match_content_end
        inc edi
        inc esi
        loop .match_content_start

    .match_content_end: ;指向下一个
        mov ebx,ecx
        pop esi
        pop edi
        pop edx
        pop ecx
        cmp ebx,0x00
            jne .match_next

        sub edi,0x05    ;使其指向命令操作数
        jmp .exit

seperate_word_by_space:

    push ebx
    mov ebx,esi
    .seperate_start:
        mov byte cl,[ds:ebx]
        inc ebx
        cmp cl,0x20
            je .seperate_start  ;跳过前面的空格键

        cmp cl,0x20
            jng .string_end
    
        mov esi,ebx
    
    .continue:
        mov byte cl,[ds:ebx]
        inc ebx
        cmp cl,0x20
            jg .continue

    .seperate_end:
        sub ebx,esi
        mov ecx,ebx
        dec esi
        pop ebx
        ret 

    .string_end:
        xor ecx,ecx
        pop ebx
        ret

;此函数用于对一个字符串进行分词并描述
;@params:
;    esi:
;    ds:指向字符串所在段
;@return:
;    edi:0x01 表示字符串结尾了。esi位置不变，ecx长度不变。
;        0x02 表示行末,esi自动指向下一个起始。
;        0x03 特殊字符
;        0x04 普通变量名称
;        0x05 标号变量名称   ;必须是紧跟着的
;        0x06 字符串类型，例如 “string text”
;        0x07 10进制纯数字类型，例如123456789
;        0x08 16进制纯数字类型，例如0xffff   ;支持大小写混用
;        0x09 二进制纯数字类型，例如0000_0001B/0000_0010_b/0001_0000b ;都是可以的。
;        0x00 表示分词出现错误,无法识别类型或者类型错误。直接就一个byte ecx为1了
;
;    esi:保存了字符串指向。
;    ecx:保存了字符串总长度。便于指向下一个。而分析时会自动跳过所有的空格。
;使用方式：近程调用
;注意事项：分词不对结果负责，需要调用者自己去处理和判断。
seperate_word_with_type:
    push eax 
    push ebx 
    push edx 

    xor eax,eax 
    mov ebx,esi 
    .skip_space:     ;首先还是需要跳过空格
        mov byte al,[ds:ebx]
        inc ebx
        cmp al,0x20 
            je .skip_space
            jg .printable_start
        cmp al,0x0d
            je .end_of_line
        cmp al,0x00 
            je .end_of_string

        xor edi,edi
        xor ecx,ecx 
        jmp .exit 

    .printable_start:     ;遇到可打印字符开始分析,第一步需要分析开头首字母
        dec ebx
        mov esi,ebx
        cmp al,'_'
            je .continue_seperate
        cmp al,'"'
            je .whether_string_type
        cmp al,','
            je .special_symbol
        cmp al,122
            jg .special_symbol
        cmp al,96
            jg .continue_seperate
        cmp al,90
            jg .special_symbol
        cmp al,64
            jg .continue_seperate
        cmp al,57
            jg .special_symbol
        cmp al,47
            jg .whether_number_type
        cmp al,32
            jg .special_symbol
        jmp .illegal_type ;其余均是非法的类型

    .continue_seperate:
        inc ebx
        mov byte al,[ds:ebx]
        cmp al,'_'    ;下划线作为不结束的特殊字符，需要单独处理。
            je .continue_seperate
        cmp al,0x20 
            je .seperate_end
        cmp al,58
            je .is_label_type 
        cmp al,','
            je .seperate_end
        cmp al,122
            jg .seperate_end
        cmp al,96
            jg .continue_seperate
        cmp al,90
            jg .seperate_end
        cmp al,64
            jg .continue_seperate
        cmp al,57
            jg .seperate_end
        cmp al,47
            jg .continue_seperate

        .seperate_end:    ;0x0d以及0x00 都会是导致合法结束。
            mov ecx,ebx
            sub ecx,esi
            mov edi,STRING_TYPE_NORMAL
            jmp .exit 

    .is_label_type:
        mov ecx,ebx
        sub ecx,esi
        inc ecx 
        mov edi,STRING_TYPE_LABEL
        jmp .exit

    .whether_string_type:
        inc ebx
        mov byte al,[ds:ebx]
        cmp al,'"'
            je .string_type 
        cmp al,0x1f  
            jg .whether_string_type
        ;等于空格或者换行其他的情况，直接设置不合法
    .illegal_type:
        mov ecx,0x01 
        mov edi,STRING_TYPE_UNKNOWN
        jmp .exit 

    .string_type:
        mov edi,STRING_TYPE_STRING
        mov ecx,ebx
        sub ecx,esi 
        inc ecx 
        jmp .exit 

    .special_symbol:    ;特殊字符
        mov ecx,0x01 
        mov edi,STRING_TYPE_SYMBOL
        jmp .exit

    .whether_number_type:
        inc ebx
        mov byte al,[ds:ebx]
        cmp al,57
            jg .illegal_type
        cmp al,47
            jg .whether_number_type
        cmp al,0x20 
            jg .illegal_type
        
        mov edi,STRING_TYPE_DECIMAL
        mov ecx,ebx
        sub ecx,esi
        jmp .exit 

    .end_of_line:    ;遇到行末则自动将esi指向下一行。如果没有，则表示结束，esi的值不变
        mov byte al,[ds:ebx]
        cmp al,0x20 
            jg .continue_line_end
        cmp al,0x0d 
            je .continue_line_end
        cmp al,0x00
            je .end_of_string
        inc ebx
        jmp .end_of_line   ;其他类型值则直接跳过。

    .continue_line_end:
        mov esi,ebx
        mov edi,STRING_TYPE_LINE_END
        mov ecx,0x00     ;为了配合添加的add esi,ecx指令，所以需要ecx为0，因为esi自动指向了下一个字符。
        jmp .exit 

    .end_of_string:
        mov edi,STRING_TYPE_END 
        jmp .exit 

    .exit:
        pop edx
        pop ebx
        pop eax 
        ret 

show_settings_message:
    push ecx
    push edi
    mov ecx,[cs:program_linear_address]
    add esi,ecx
    mov ecx,0x100
    mov edi,0x01
    call far [cs:common_service_entry]
    pop edi
    pop ecx
    ret

label_address dd 0x0000_0004   ;代码段偏移地址,从第4个字节开始，因为前4个字节代表了程序大小。
argument_address dd 0x0000_0000   ;数据段偏移
line_number dd 0x0000_0001   ;行号，用于错误信息的显示

;============================================================
STRING_TYPE_UNKNOWN equ 0x00
STRING_TYPE_END equ 0x01
STRING_TYPE_LINE_END equ 0x02 
STRING_TYPE_SYMBOL equ 0x03 
STRING_TYPE_LABEL equ 0x04
STRING_TYPE_NORMAL equ 0x05
STRING_TYPE_STRING equ 0x06
STRING_TYPE_DECIMAL equ 0x07

settings_message:
message_start db 'Initializing compile servi  ce...\n',0
message_error db '\ncompile error:',0x60,0
message_command_not_exists db 0x60,' Command not exists.',0
message_argments_not_exists db '->debug:argments not exists.\n',0
message_argments_exists db '->debug:compile argument.\n',0
message_illegle_syntax db '->debug:illegle syntax\n',0
message_illegle_start db '->debug:illegle start\n',0
message_illegle_command db '->debug:can not be argument\n',0
message_syntax_correct db '->debug:syntax all words correct\n',0
message_illegle_arg2_not_exits db '->debug:argument2 does not exist\n',0
message_illegle_empty_arg db '->debug:arguments can not be empty\n',0
message_arg_string_type db '->debug:this is a string\n',0
message_illegle_first_params db '->debug:can not be an argument.\n',0
message_illegle_name db '->debug:can not be a name.\n',0
message_illegle_command_extra_arg db '->debug:extra argument.',0
illegle_argument_length_wrong db '->debug:argument length wrong.',0
illegle_argument_can_not_find db '->compile error:argument_can_not_find.',0

message_syntax_illegle_type_line_start db '->compile error:illegle line start.\n',0
message_syntax_illegle_name_start db '->compile error:illegle name start.\n',0
message_syntax_illegle_command_missing_arg db '->compile error:argument is missing.\n',0
message_syntax_illegle_command_can_not_be_argument db '->compile error:command can not be argument.\n',0
message_syntax_illegle_end_line db '->compile error:extra argument or letter.\n',0
message_syntax_illegle_arg1_type db '->compile error:wrong argument type.\n',0
message_syntax_illegle db '->compile error:unknown error.\n',0
message_syntax_illegle_unknown_command db '->compile error:unknown command.\n',0
message_syntax_illegle_label_inconsistently_redfined db '->compile error:label name inconsistently redfined.\n',0
message_syntax_is_label db '->this is a label.\n',0
message_label_not_exists db '->compile error:label not exist.\n',0
message_argument_not_defined db '->compile error:argument not defined.\n',0
illegle_argument_wrong_type db '->compile error:argument wrong type.\n',0

string_message_wrong_label_end db '->syntax error:label illegal end.\n',0
string_message_illegal_line_start db '->syntax error:please start with command or label\n',0
string_message_label_redefined db '->syntax error:label inconsistently redefined.\n',0
string_message_command_missing_parameter db '->syntax error:argument is missing.\n',0
string_message_illegal_name db '->syntax error:illegal name.\n',0
string_message_illegal_argument db '->syntax error:illegal argument.\n',0
string_message_illegal_argument2_not_exists db '->syntax error:argument2 does not exists.\n',0
string_message_illegal_command_ending db '->syntax error:illegal command ending.\n',0
string_message_illegal_extra_letters_ending db '->syntax error:extra letters or symbol.\n',0
string_message_unknown_command db '->syntax error:unknown command.\n',0
string_message_command_can_not_be_argument db '->syntax error:reserved word can not be argument.\n',0
string_message_line db ' (line ',0
string_message_line_end db ')',0
;==========================命令表区==============================
db 0x00
dw 0x0000    
dw 0x0000   ;5个字节的空指令
db 0x00     ;编译范式类型     ;0x00;无操作数，0x01，一个操作数，0x02,两个操作数

dw 0x0001    ;公共服务,两个字节的服务数
dw 0x00       ;长度为0，直接就是打印输出某个地址
db 0x01      ;一个参数
command_table:
db 0x04
db 'echo'

dw 0x000e    ;内部指令
dw 0x00      ;长度为0，直接就是打印输出某个地址
db 0x01      ;一个参数
db 0x03
db 'inc'

dw 0x000f    ;内部指令
dw 0x00      ;长度为0，直接就是打印输出某个地址
db 0x02      ;2个参数
db 0x03
db 'add'

dw 0x0010    ;内部指令
dw 0x00      ;长度为0，直接就是打印输出某个地址
db 0x01      ;一个参数
db 0x03
db 'dec'

dw 0x0011    ;内部指令
dw 0x00      ;长度为0，直接就是打印输出某个地址
db 0x02      ;2个参数
db 0x03
db 'sub'

dw 0x0032    ;公共服务,两个字节的服务数
dw 0x01      ;长度为1，这样就可以先使用再定义了。预处理也就是预加载。
db 0x01      ;一个参数
db 0x04
db 'jump'

dw 0x33
dw 0x00     ;长度为0，直接就是关机操作
db 0x02      ;两个参数
db 0x06
db 'repeat'

dw 0x0001    ;公共服务,两个字节的服务数
dw 0x00       ;长度为0，直接就是打印输出某个地址
db 0x01      ;一个参数
db 0x06  
db 'prints'

dw 0x0007    ;公共服务,两个字节的服务数
dw 0x00       ;长度为0，直接就是打印输出某个地址
db 0x01      ;一个参数
db 0x0a
db 'stayPrints'

dw 0x0002
dw 0x01     ;长度为0，直接就是打印输出某个字符或者字符串的第一位
db 0x01      ;一个参数
db 0x08
db 'echochar'

dw 0x0005
dw 0x00     ;长度为0，直接就是清屏操作
db 0x00      ;没有参数
db 0x03
db 'cls'

dw 0x65
dw 0x00     ;长度为0，直接就是关机操作
db 0x00      ;没有参数
db 0x08
db 'shutdown'

dw 0x13
dw 0x04     ;长度为4，睡眠
db 0x01      ;1个参数
db 0x05
db 'sleep'

dw 0x76
dw 0x40     ;变量数据长度为64，创建文件夹，后面可以跟字符串
db 0x01      ;一个参数
db 0x04
db 'edit'     ;文件编辑命令

dw 0x66
dw 0x00     ;长度为0，显示时间操作
db 0x00      ;没有参数
db 0x04
db 'time'

dw 0x67    ;103日期服务
dw 0x00
db 0x00      ;没有参数
db 0x04
db 'date'

dw 0x68    ;104获取时间字符串
dw 64       ;长度64个字节的字符串
db 0x01      ;一个参数
db 0x0d
db 'getTimeString'

dw 0x69    ;105获取日期字符串
dw 64       ;长度64个字节的字符串
db 0x01      ;一个参数
db 0x0d
db 'getDateString'

dw 0xc8
dw 0x00     ;长度为0，显示的是pci端口
db 0x00      ;没有参数
db 0x05
db 'lspci'     ;显示PCI设备

dw 0x12c        ;300文件服务号
dw 0x00     ;长度为0，显示文件列表，后面不能跟操作数。
db 0x00      ;没有参数
db 0x02
db 'ls'

dw 0x12d
dw 0x40     ;变量数据长度为64，创建文件夹，后面可以跟字符串
db 0x01      ;一个参数
db 0x05
db 'mkdir'     ;新建文件夹

dw 0x12e        ;300文件服务号
dw 0x40
db 0x01      ;一个参数
db 0x02
db 'cd'

dw 0x12f        ;300文件服务号
dw 0x40     ;长度为64字节，打开文件列表
db 0x00      ;没有参数
db 0x04
db 'cd..'

dw 0x0130
dw 0x00     ;长度为0，打开根目录
db 0x00      ;没有参数
db 0x04
db 'cd.\'

dw 0x0131
dw 0x40     ;长度为64字节，创建二进制文件
db 0x01      ;一个参数
db 0x02
db 'nf'

dw 0x0132
dw 0x40     ;长度为64字节，删除文件
db 0x01      ;一个参数
db 0x06
db 'delete'

dw 0x0131
dw 0x40     ;长度为64字节，创建二进制文件
db 0x01      ;一个参数
db 0x07
db 'newfile'

dw 0x71
dw 0x00     ;长度为0，列出任务
db 0x00      ;没有参数
db 0x06
db 'lstask'

dw 0x72
dw 0x40     ;长度为64字节，关闭某个应用程序
db 0x01      ;一个参数
db 0x05
db 'close'

dw 0x70
dw 0x40     ;长度为64字节，打开某个应用程序
db 0x01      ;一个参数
db 0x04
db 'open'

dw 0x77
dw 0x40     ;长度为64字节，打开某个应用程序
db 0x01      ;一个参数
db 0x04
db 'stop'

dw 0x78
dw 0x40     ;长度为64字节，打开某个应用程序
db 0x01      ;一个参数
db 0x05
db 'start'

dw 0x73
dw 0x40     ;长度为64字节，打开某个应用程序
db 0x02      ;2个参数
db 0x07
db 'copysec'

dw 0x74
dw 0x40
db 0x01      ;一个参数
db 0x07
db 'showsec'

dw 0x75
dw 0x00
db 0x00      ;没有参数
db 0x04
db 'help'

dw 0x0d      ;13号命令
dw 0x00
db 0x02      ;2个参数
db 0x04
db 'copy'   ;复制两个变量的值，这一条语句的执行，是需要修改掉相关的运行命令的

dw 0x190
dw 0x00
db 0x00
db 0x09
command_table_end:
db 'netlisten'   ;网络监听服务

times 512-($-command_table) db 0

;-------------------------------------
;此段用于创建一个文件名描述符表。

arguments_table:

arguments_table_pointer dd arguments_table_start
arguments_table_start:
;dd compile_buffer_start    ;参数的偏移地址。
;dw 0x40    ;参数的数据长度。  ;最大单个数据长度为65535个字节。
;db 0x04    ;参数的名称长度。
;db 'test'
arguments_table_end:

times 2048-($-arguments_table_pointer) db 0

;------------------------------------------
;编译缓存段，编译后的指令将会存放到这里。
compile_buffer:
compile_buffer_pointer dd compile_buffer_start
;dw compile_buffer_start    ;应用程序入口点
;dd 0x00000000   ;应用程序段地址
;dw compile_buffer_start    ;数据起始地址

compile_buffer_start:

compile_buffer_end:
times 2048-($-compile_buffer_pointer) db 0

SECTION tail
program_end:
