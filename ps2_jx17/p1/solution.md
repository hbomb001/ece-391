### P1 Solution

#### 1. Split Screen
To separate the windows vertically, we can use split-screen operation to have two independent horizontal divisions. The starting memory address of the bottom division is always 0, while the starting memory address of the top division is specified by __Start Address Register__ (consisting of __Start Address High Register__ and __Start Address Low Register__). The separation scan line number is controlled by __Line Compare Field__, of which bit 9 is in __Maximum Scan Line Register__, bit 8 in __Overflow Register__, and bits 7-0 are in the __Line Compare Register__. Whenever line counter reaches this value current scan line address is reset to 0, which means VGA finishes drawing of the top division and starts to draw the bottom division. To disable the panning function of the bottom division (status bar), we need to set __Pixel Panning Mode__ (bit 5 of __Attribute Mode Control Register__) to 0. Now that the bottom division is fixed, we may control the panning and scrolling of the top division by __Pixel Shift Count field__, __Byte Panning field__. Additional pixel-level scrolling can be controlled by __Preset Row Scan__ in which the maximum value is defined in __Maximum Scan Line__.
##### Constraints:
Value of __Start Address Register__ should be large enough so that memory for the bottom division can fit into memory address 0-(__Start Address Register__-1).

#### 2. Change Color Palette
First output the palette entry’s index value to __DAC Address Write Mode Register__ (port 3C8h) and then perform 3 consecutive writes to the __DAC Data Register__ (port 3C9h), first red followed by green followed by blue. The internal write address will auto increment after that, allowing the writing to the next address without reprogramming __DAC Address Write Mode Register__ (port 3C8h).

1. Output the index value of the first palette entry to the __DAC Address Write Mode Register__ (port 3C8h)
1. Write the __DAC Data Register__ (port 3C9h) to obtain the red component value
1. Write the __DAC Data Register__ (port 3C9h) to obtain the green component value
1. Write the __DAC Data Register__ (port 3C9h) to obtain the blue component value
1. If more colors are to be written in the next palette index, repeat steps 2-4
