use dep::std::option::Option;
use dep::protocol_types::constants::MAX_READ_REQUESTS_PER_CALL;
use crate::value_note::ValueNote;

pub fn filter_notes_min_sum(notes: [Option<ValueNote>; MAX_READ_REQUESTS_PER_CALL], min_sum: Field) -> [Option<ValueNote>; MAX_READ_REQUESTS_PER_CALL] {
    let mut selected = [Option::none(); MAX_READ_REQUESTS_PER_CALL];
    let mut sum = 0;
    for i in 0..notes.len() {
        if notes[i].is_some() & (sum < min_sum as u120) {
            let note = notes[i].unwrap_unchecked();
            selected[i] = Option::some(note);
            sum += note.value as u120;
        }
    }
    selected
}
