using Matcha

isunless(x::Expr) = x.head == :gotoifnot
isunless(x) = false
islabelnode(x::LabelNode) = true
islabelnode(x) = false
isgoto(x::GotoNode) = true
isgoto(x) = false

function is_unless_label(label, hist, histpos = 1)
    islabelnode(label) || return false
    unless = hist[histpos][1]
    unless_label = unless.args[2]
    unless_label == label.label
end
function is_goto_label(label, hist, histpos)
    islabelnode(label) || return false
    goto = hist[histpos][1]
    goto.label == label.label
end
function is_goto(goto, hist, histpos)
    isgoto(goto) || return false
    label = hist[histpos][1]
    goto.label == label.label
end


ifelse_pattern = (
    isunless, # if branch
    anything, # if body
    isgoto, # goto to jump over else
    (l, h)-> is_unless_label(l, h, 1),
    anything,   # else body
    (l, h)-> is_goto_label(l, h, 3) # label matching above goto
)
while_pattern = (
    islabelnode, # loop goto label
    isunless, # while condition branch
    anything, # body
    Greed(islabelnode, 0:1), # optional continue label
    (l,h)-> is_goto(l, h, 1), # goto label, matching first label
    (l,h)-> is_unless_label(l, h, 2) # goto and break
)

if_pattern = (isunless, anything, is_unless_label)

"""
Replaces `goto` statements in a loop body with continue and break.
"""
function replace_continue_break(astlist, continue_label, break_label)
    map(astlist) do elem
        if isa(elem, GotoNode) && elem.label == continue_label.label
            Expr(:continue)
        elseif isa(elem, GotoNode) && elem.label == break_label.label
            Expr(:break)
        else
            elem
        end
    end
end
function remove_goto(ast)
    ast = matchreplace(ast, ifelse_pattern) do unless, ifbody, _1, _2, elsebody, _3
        condition = unless[1].args[1]
        ifbody = Expr(:block, remove_goto(collect(ifbody))...)
        elsebody = Expr(:block, remove_goto(collect(elsebody))...)
        Expr(:if, condition, ifbody, elsebody)
    end
    ast = matchreplace(ast, while_pattern) do loop_label, unless, whilebody, continue_label, goto, break_label
        condition = unless[1].args[1]
        whilebody = replace_continue_break(collect(whilebody), continue_label[1], break_label[1])
        whilebody = remove_goto(whilebody)
        block = Expr(:block, whilebody...)
        Expr(:while, condition, block)
    end
    ast = matchreplace(ast, if_pattern) do unless, body, label
        condition = unless[1].args[1]
        ifbody = Expr(:block, remove_goto(collect(body))...)
        Expr(:if, condition, ifbody)
    end
    ast
end

function test(a, b)
    if a == 10
        x = if b == 22
            7
        else
            8
        end
        for i=1:100
            x += i
            x -= 77
            if i == 77
                continue
            elseif i == 99
                break
            end
        end
        return x
    else
        return 77
    end
end
ast = Base.uncompressed_ast(code_lowered(test, (Int, Int))[])
filter!(x-> x != nothing && !isa(x, LineNumberNode), ast)

ast2 = remove_goto(ast)
ast2
