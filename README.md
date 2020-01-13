**ivy-cscope.el** provides yet another interface for Cscope in Emacs.

It uses [ivy](https://github.com/abo-abo/swiper)
to display and select the cscope jump candidates.  It also uses "ivy
actions" to perform rich actions (e.g. open other window, open other
window without focus) on the jump candidates.

It provides
- `ivy-cscope-find-xxx`: 9 functions each for cscope's menu
  (e.g. symbol, definition, assignment, calling, ...).
- `ivy-cscope-find-definition-at-point`: a handy command to find the
  definition of the symbol at point.
- `ivy-cscope-pop-mark`: jump back to the location before the
  last `ivy-cscope-xxxx` jump."
- `ivy-cscope-command-map`: a keymap of all the commands
  above.

### Example:

#### Bind the key map:

```elisp
    (define-key c-mode-base-map (kbd "C-c j c") ivy-cscope-command-map)
```

#### Also for quick access:

```elisp
    (define-key c-mode-base-map (kbd "M-.") 'ivy-cscope-find-definition-at-point)
    (define-key c-mode-base-map (kbd "M-,") 'ivy-cscope-pop-mark)
    (define-key c-mode-base-map [M-mouse-1] 'ivy-cscope-find-definition-at-point)
    (define-key c-mode-base-map [M-S-mouse-1] 'ivy-cscope-pop-mark)
````

#### Get familiar with ivy actions:

1. Press "C-c j c c" (or "M-x ivy-cscope-find-caller").

2. Insert "put_user_pages" to find functions calling "put_user_pages".

3. A completion list shows up, like

```
    (1/3) Result:
    drivers/infiniband/core/umem_odp.c ...
    fs/io_uring.c ...
    mm/gup.c ...
```

4. He can move to the second line and press "M-o" to trigger ivy actions.
   A list of actions are shown, for example, open the result in other window,
   open the result in other window without focus, ....
 
#### Other hints when using ivy completion (not directly related to this package)

Bind `ivy-avy` (if you use [avy](https://github.com/abo-abo/avy)) for quick selection:

```elisp
(define-key ivy-minibuffer-map (kbd "M-'") 'ivy-avy)
```

When in ivy minibuffer, one can use 
- `C-M-m` to preview the current candidate (select the candidate while remain the point in the minibuffer).
- `C-M-n` to preview the next candidate.
- `C-M-p` to preview the previous candidate.
- `C-g` to abort the preview.

### Other Emacs cscope packages:
- [xcscope.el](https://github.com/dkogan/xcscope.el)

