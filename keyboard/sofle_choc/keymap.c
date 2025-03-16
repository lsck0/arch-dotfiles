#include QMK_KEYBOARD_H

#define DE_SS KC_MINS // ß
#define DE_AE KC_QUOT // ä
#define DE_UE KC_LBRC // ü
#define DE_OE KC_SCLN // ö

#define DE_CIRC KC_GRAVE // accent circumflex ^ and ring °
#define DE_ACUT KC_EQL   // accent acute ´ and grave `
#define DE_PLUS KC_RBRC  // + and * and ~
#define DE_HASH KC_BSLS  // # and '
#define DE_LESS KC_NUBS  // < and > and |
#define DE_MINS KC_SLSH  // - and _

// shifted characters
#define DE_RING LSFT(DE_CIRC) // °
#define DE_EXLM LSFT(KC_1)    // !
#define DE_DQOT LSFT(KC_2)    // "
#define DE_PARA LSFT(KC_3)    // §
#define DE_DLR  LSFT(KC_4)    // $
#define DE_PERC LSFT(KC_5)    // %
#define DE_AMPR LSFT(KC_6)    // &
#define DE_SLSH LSFT(KC_7)    // /
#define DE_LPRN LSFT(KC_8)    // (
#define DE_RPRN LSFT(KC_9)    // )
#define DE_EQL  LSFT(KC_0)    // =
#define DE_QST  LSFT(DE_SS)   // ?
#define DE_GRV  LSFT(DE_ACUT) // `
#define DE_ASTR LSFT(DE_PLUS) // *
#define DE_QUOT LSFT(DE_HASH) // '
#define DE_MORE LSFT(DE_LESS) // >
#define DE_COLN LSFT(KC_DOT)  // :
#define DE_SCLN LSFT(KC_COMM) // ;
#define DE_UNDS LSFT(DE_MINS) // _

// Alt Gr-ed characters
#define DE_SQ2  ALGR(KC_2)    // ²
#define DE_SQ3  ALGR(KC_3)    // ³
#define DE_LCBR ALGR(KC_7)    // {
#define DE_LBRC ALGR(KC_8)    // [
#define DE_RBRC ALGR(KC_9)    // ]
#define DE_RCBR ALGR(KC_0)    // }
#define DE_BSLS ALGR(DE_SS)   // backslash
#define DE_AT   ALGR(KC_Q)    // @
#define DE_EURO ALGR(KC_E)    // €
#define DE_TILD ALGR(DE_PLUS) // ~
#define DE_PIPE ALGR(DE_LESS) // |

enum layers {
    _BASE,
    _LOWER,
    _UPPER,
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
/*
 * BASE LAYER
 * ,-----------------------------------------.                    ,-----------------------------------------.
 * | ESC  |   1  |   2  |   3  |   4  |   5  |                    |   6  |   7  |   8  |   9  |   0  | Bspc |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * | TAB  |   Q  |   W  |   E  |   R  |   T  |                    |   Z  |   U  |   I  |   O  |   P  |  Ü   |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * | LCTL |   A  |   S  |   D  |   F  |   G  |-------.    ,-------|   H  |   J  |   K  |   L  |   Ö  |  Ä   |
 * |------+------+------+------+------+------|  Mute |    | Pause |------+------+------+------+------+------|
 * |LShift|   Y  |   X  |   C  |   V  |   B  |-------|    |-------|   N  |   M  |   ,  |   .  |   -  |RShift|
 * `-----------------------------------------/       /     \      \-----------------------------------------'
 *            |      | LCMD | LALT |LOWER | /Space  /       \Enter \  |RAISE | RALT |      |      |
 *            |      |      |      |      |/       /         \      \ |      |      |      |      |
 *            `----------------------------------'           '------''---------------------------'
 */
[_BASE] = LAYOUT(
    KC_ESC,   KC_1,  KC_2,   KC_3,     KC_4,     KC_5,                            KC_6,        KC_7,     KC_8,     KC_9,    KC_0,      KC_BSPC,
    KC_TAB,   KC_Q,  KC_W,   KC_E,     KC_R,     KC_T,                            KC_Y,        KC_U,     KC_I,     KC_O,    KC_P,      DE_UE,
    KC_LCTL,  KC_A,  KC_S,   KC_D,     KC_F,     KC_G,                            KC_H,        KC_J,     KC_K,     KC_L,    DE_OE,     DE_AE,
    KC_LSFT,  KC_Z,  KC_X,   KC_C,     KC_V,     KC_B,        KC_MUTE,  KC_MPLY,  KC_N,        KC_M,     KC_COMM,  KC_DOT,  KC_MINUS,  KC_RSFT,
                     KC_NO,  KC_LCMD,  KC_LALT,  MO(_LOWER),  KC_SPC,   KC_ENT,   MO(_UPPER),  KC_RALT,  KC_NO,    KC_NO
),
/*
 * LOWER LAYER
 * ,-----------------------------------------.                    ,-----------------------------------------.
 * |  F1  |  F2  |  F3  |  F4  |  F5  |  F6  |                    |  F7  |  F8  |  F9  | F10  | F11  | F12  |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * |      |      |      |      |      |      |                    |      |      |      |      |      |      |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * |      |      |      |      |      |      |-------.    ,-------| left | down |  up  | right|      |      |
 * |------+------+------+------+------+------|       |    |       |------+------+------+------+------+------|
 * |      |      |      |      |      |      |-------|    |-------|      |      |      |      |      |      |
 * `-----------------------------------------/       /     \      \-----------------------------------------'
 *            |   Q  |      |      |      | /       /       \      \  |      |      |      |      |
 *            |      |      |      |      |/       /         \      \ |      |      |      |      |
 *            `----------------------------------'           '------''---------------------------'
 */
[_LOWER] = LAYOUT(
    KC_F1,  KC_F2,  KC_F3,  KC_F4,  KC_F5,  KC_F6,                 KC_F7,    KC_F8,    KC_F9,  KC_F10,   KC_F11,  KC_F12,
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,    KC_NO,    KC_NO,  KC_NO,    KC_NO,   KC_NO,
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_LEFT,  KC_DOWN,  KC_UP,  KC_RGHT,  KC_NO,   KC_NO,
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO, KC_NO,  KC_NO,    KC_NO,    KC_NO,  KC_NO,    KC_NO,   KC_NO,
                    KC_Q,   KC_NO,  KC_NO,  KC_NO,  KC_NO, KC_NO,  KC_NO,    KC_NO,    KC_NO,  KC_NO
),
/*
 * UPPER LAYER
 * ,-----------------------------------------.                    ,-----------------------------------------.
 * |      |      |      |      |      |      |                    |      |      |      |      |      |      |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * |      |      |      |      |      |      |                    |      |      |      |      |      |      |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * |      |      |      |      |      |      |-------.    ,-------|      |      |      |      |      |      |
 * |------+------+------+------+------+------|       |    |       |------+------+------+------+------+------|
 * |      |      |      |      |      |      |-------|    |-------|      |      |      |      |      |      |
 * `-----------------------------------------/       /     \      \-----------------------------------------'
 *            |      |      |      |      | /       /       \      \  |      |      |      |      |
 *            |      |      |      |      |/       /         \      \ |      |      |      |      |
 *            `----------------------------------'           '------''---------------------------'
 */
[_UPPER] = LAYOUT(
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,
    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO, KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,
                    KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO, KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO
),
/*
 * EMPTY LAYER
 * ,-----------------------------------------.                    ,-----------------------------------------.
 * |      |      |      |      |      |      |                    |      |      |      |      |      |      |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * |      |      |      |      |      |      |                    |      |      |      |      |      |      |
 * |------+------+------+------+------+------|                    |------+------+------+------+------+------|
 * |      |      |      |      |      |      |-------.    ,-------|      |      |      |      |      |      |
 * |------+------+------+------+------+------|       |    |       |------+------+------+------+------+------|
 * |      |      |      |      |      |      |-------|    |-------|      |      |      |      |      |      |
 * `-----------------------------------------/       /     \      \-----------------------------------------'
 *            |      |      |      |      | /       /       \      \  |      |      |      |      |
 *            |      |      |      |      |/       /         \      \ |      |      |      |      |
 *            `----------------------------------'           '------''---------------------------'
 */
/*[_EMPTY] = LAYOUT(*/
    /*KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,*/
    /*KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,*/
    /*KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,                 KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,*/
    /*KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO, KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO,*/
                    /*KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO, KC_NO,  KC_NO,  KC_NO,  KC_NO,  KC_NO*/
/*),*/
};

#if defined(ENCODER_MAP_ENABLE)
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][NUM_DIRECTIONS] = {
    [_BASE] = {
        ENCODER_CCW_CW(KC_VOLD, KC_VOLU), // left  rot encoder
        ENCODER_CCW_CW(KC_MPRV, KC_MNXT), // right rot encoder
    },
    [_LOWER] = {
        ENCODER_CCW_CW(KC_VOLD, KC_VOLU),
        ENCODER_CCW_CW(KC_MPRV, KC_MNXT),
    },
    [_UPPER] = {
        ENCODER_CCW_CW(KC_VOLD, KC_VOLU),
        ENCODER_CCW_CW(KC_MPRV, KC_MNXT),
    },
};
#endif

#ifdef OLED_ENABLE
// 32x128 px displays

static const char PROGMEM qmk_logo[] = {
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a,
    0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0xa0,
    0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab,
    0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xc0, 0xc1,
    0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcc,
    0xcd, 0xce, 0xcf, 0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0
};

oled_rotation_t oled_init_user(oled_rotation_t rotation) {
  if (is_keyboard_master()) {
    return OLED_ROTATION_270;
  }
  return rotation;
}

bool oled_task_user(void) {
  if (!is_keyboard_master()) {
    oled_write_P(qmk_logo, false);
    return false;
  }

  oled_write_P(PSTR("LAYER\n"), false);
  switch (get_highest_layer(layer_state)) {
      case _BASE:  oled_write_P(PSTR("Base\n") , false); break;
      case _LOWER: oled_write_P(PSTR("Lower\n"), false); break;
      case _UPPER: oled_write_P(PSTR("Upper\n"), false); break;
      default:     oled_write_P(PSTR("Undef\n"), false); break;
  }

  return false;
}

#endif
