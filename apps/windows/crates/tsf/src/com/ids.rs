use windows_core::GUID;

pub const CLSID_TEXT_SERVICE: GUID = GUID::from_u128(0xeb1c48da_a029_48bc_8f14_9ab36d3f1fbc);
pub const GUID_PROFILE: GUID = GUID::from_u128(0x240dda33_3137_46f6_86e5_b7eb79b110f4);

pub const GUID_ATTRIBUTE_READING: GUID = GUID::from_u128(0x8af2da83_0cf1_4f27_a9f7_7313325cfa48);
pub const GUID_ATTRIBUTE_CONVERTED: GUID = GUID::from_u128(0x4804b68b_27bc_460e_bed0_ccfbbc760b95);
pub const GUID_ATTRIBUTE_FOCUSED: GUID = GUID::from_u128(0x538b6f8c_9999_4c90_aa25_9b539f837e6d);
pub const GUID_ATTRIBUTE_CORRECTION: GUID = GUID::from_u128(0xb3263560_ea70_4d14_b90e_dc84d6e56310);

pub const SERVICE_NAME: &str = "s90.tokyo IME";
pub const LANGID_JAPANESE: u16 = 0x0411;
