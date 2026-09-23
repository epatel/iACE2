/* Jupiter ACE keyboard matrix, copyright (C) 2012 Lawrence Woodman, (C) 2012-2026 Edward Patel.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * Maps ACE character codes to the keys that produce them. Ports are the eight half-rows
 * read through IN 0xFE (active low); a mask selects the key bit(s) in that half-row.
 * Port 0 bit 0 is SHIFT and bit 1 is SYMBOL SHIFT.
 *
 * Differences from iACE 1.x: 'z' was coded 0x80 (so it could not be typed), BREAK shared its
 * code with '&', and the pound and copyright signs used 0x9C/0x60. Here BREAK is 0x1B and the
 * ACE character set positions are used: pound 0x60, copyright 0x7F.
 */

#include "ace_internal.h"

enum {
    KEY_DELETE_LINE = 0x01,
    KEY_INVERSE_VIDEO = 0x02,
    KEY_GRAPHICS = 0x03,
    KEY_LEFT = 0x04,
    KEY_DOWN = 0x05,
    KEY_UP = 0x06,
    KEY_RIGHT = 0x07,
    KEY_DELETE = 0x08,
    KEY_TAB = 0x09,
    KEY_RETURN = 0x0a,
    KEY_BREAK = 0x1b,
};

/* char, port1, and-mask1, port2, and-mask2 (port2 == -1: none) */
static const int keys[][5] = {
    {KEY_DELETE_LINE, 3, 0xfe, 0, 0xfe},
    {KEY_INVERSE_VIDEO, 3, 0xf7, 0, 0xfe},
    {KEY_GRAPHICS, 4, 0xfd, 0, 0xfe},
    {KEY_LEFT, 3, 0xef, 0, 0xfe},
    {KEY_DOWN, 4, 0xf7, 0, 0xfe},
    {KEY_UP, 4, 0xef, 0, 0xfe},
    {KEY_RIGHT, 4, 0xfb, 0, 0xfe},
    {KEY_DELETE, 0, 0xfe, 4, 0xfe},
    {KEY_TAB, 7, 0xfe, -1, 0},
    {KEY_RETURN, 6, 0xfe, -1, 0},
    {KEY_BREAK, 7, 0xfe, 0, 0xfe},
    {'1', 3, 0xfe, -1, 0},
    {'2', 3, 0xfd, -1, 0},
    {'3', 3, 0xfb, -1, 0},
    {'4', 3, 0xf7, -1, 0},
    {'5', 3, 0xef, -1, 0},
    {'6', 4, 0xef, -1, 0},
    {'7', 4, 0xf7, -1, 0},
    {'8', 4, 0xfb, -1, 0},
    {'9', 4, 0xfd, -1, 0},
    {'0', 4, 0xfe, -1, 0},
    {'!', 3, 0xfe, 0, 0xfd},
    {'@', 3, 0xfd, 0, 0xfd},
    {'#', 3, 0xfb, 0, 0xfd},
    {'$', 3, 0xf7, 0, 0xfd},
    {'%', 3, 0xef, 0, 0xfd},
    {'&', 4, 0xef, 0, 0xfd},
    {'\'', 4, 0xf7, 0, 0xfd},
    {'(', 4, 0xfb, 0, 0xfd},
    {')', 4, 0xfd, 0, 0xfd},
    {'_', 4, 0xfe, 0, 0xfd},
    {'A', 0, 0xfe, 1, 0xfe},
    {'a', 1, 0xfe, -1, 0},
    {'B', 0, 0xfe, 7, 0xf7},
    {'b', 7, 0xf7, -1, 0},
    {'C', 0, 0xee, -1, 0},
    {'c', 0, 0xef, -1, 0},
    {'D', 0, 0xfe, 1, 0xfb},
    {'d', 1, 0xfb, -1, 0},
    {'E', 0, 0xfe, 2, 0xfb},
    {'e', 2, 0xfb, -1, 0},
    {'F', 0, 0xfe, 1, 0xf7},
    {'f', 1, 0xf7, -1, 0},
    {'G', 0, 0xfe, 1, 0xef},
    {'g', 1, 0xef, -1, 0},
    {'H', 0, 0xfe, 6, 0xef},
    {'h', 6, 0xef, -1, 0},
    {'I', 0, 0xfe, 5, 0xfb},
    {'i', 5, 0xfb, -1, 0},
    {'J', 0, 0xfe, 6, 0xf7},
    {'j', 6, 0xf7, -1, 0},
    {'K', 0, 0xfe, 6, 0xfb},
    {'k', 6, 0xfb, -1, 0},
    {'L', 0, 0xfe, 6, 0xfd},
    {'l', 6, 0xfd, -1, 0},
    {'M', 0, 0xfe, 7, 0xfd},
    {'m', 7, 0xfd, -1, 0},
    {'N', 0, 0xfe, 7, 0xfb},
    {'n', 7, 0xfb, -1, 0},
    {'O', 0, 0xfe, 5, 0xfd},
    {'o', 5, 0xfd, -1, 0},
    {'P', 0, 0xfe, 5, 0xfe},
    {'p', 5, 0xfe, -1, 0},
    {'Q', 0, 0xfe, 2, 0xfe},
    {'q', 2, 0xfe, -1, 0},
    {'R', 0, 0xfe, 2, 0xf7},
    {'r', 2, 0xf7, -1, 0},
    {'S', 0, 0xfe, 1, 0xfd},
    {'s', 1, 0xfd, -1, 0},
    {'T', 0, 0xfe, 2, 0xef},
    {'t', 2, 0xef, -1, 0},
    {'U', 0, 0xfe, 5, 0xf7},
    {'u', 5, 0xf7, -1, 0},
    {'V', 0, 0xfe, 7, 0xef},
    {'v', 7, 0xef, -1, 0},
    {'W', 0, 0xfe, 2, 0xfd},
    {'w', 2, 0xfd, -1, 0},
    {'X', 0, 0xf6, -1, 0},
    {'x', 0, 0xf7, -1, 0},
    {'Y', 0, 0xfe, 5, 0xef},
    {'y', 5, 0xef, -1, 0},
    {'Z', 0, 0xfa, -1, 0},
    {'z', 0, 0xfb, -1, 0},
    {'<', 2, 0xf7, 0, 0xfd},
    {'>', 2, 0xef, 0, 0xfd},
    {'[', 5, 0xef, 0, 0xfd},
    {']', 5, 0xf7, 0, 0xfd},
    {0x7f, 5, 0xfb, 0, 0xfd}, /* copyright */
    {';', 5, 0xfd, 0, 0xfd},
    {'"', 5, 0xfe, 0, 0xfd},
    {'~', 1, 0xfe, 0, 0xfd},
    {'|', 1, 0xfd, 0, 0xfd},
    {'\\', 1, 0xfb, 0, 0xfd},
    {'{', 1, 0xf7, 0, 0xfd},
    {'}', 1, 0xef, 0, 0xfd},
    {'^', 6, 0xef, 0, 0xfd},
    {'-', 6, 0xf7, 0, 0xfd},
    {'+', 6, 0xfb, 0, 0xfd},
    {'=', 6, 0xfd, 0, 0xfd},
    {':', 0, 0xf9, -1, 0},
    {0x60, 0, 0xf5, -1, 0}, /* pound */
    {'?', 0, 0xed, -1, 0},
    {'/', 7, 0xef, 0, 0xfd},
    {'*', 7, 0xf7, 0, 0xfd},
    {',', 7, 0xfb, 0, 0xfd},
    {'.', 7, 0xfd, 0, 0xfd},
    {' ', 7, 0xfe, -1, 0},
};

int keyboard_char_keys(int ace_char, int *port1, int *mask1, int *port2, int *mask2)
{
    for (size_t n = 0; n < sizeof(keys) / sizeof(keys[0]); n++) {
        if (keys[n][0] == ace_char) {
            *port1 = keys[n][1];
            *mask1 = ~keys[n][2] & 0xff;
            *port2 = keys[n][3];
            *mask2 = ~keys[n][4] & 0xff;
            return 1;
        }
    }
    return 0;
}
