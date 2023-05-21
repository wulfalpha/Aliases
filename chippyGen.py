#!/usr/bin/env python3
"""Programmatically generate melody and harmony, based on scale and rhythm."""
import random
import argparse
import mido
import os
import textwrap


class MusicNote:
    NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    @classmethod
    def to_midi(cls, note):
        if isinstance(note, str):
            if note == "":
                return None  # Return None for empty notes

            # Check if last character is digit (indicating an octave number)
            if note[-1].isdigit():
                note_name = note[:-1]  # All but last character as note name
                octave = int(note[-1])  # Last character is the octave
            else:
                note_name = note
                octave = 4  # Default octave

            pitch = cls.NOTE_NAMES.index(note_name)
            return (octave + 1) * 12 + pitch
        elif isinstance(note, int):
            return note


class RhythmPatterns:
    RHYTHM_PATTERNS = {
        3: [480, 240],
        4: [480, 240, 120],
        8: [480, 240],
    }

    @classmethod
    def get_rhythm(cls, meter, beat_count):
        return (
            480
            if beat_count % meter == 0
            else random.choice(cls.RHYTHM_PATTERNS[meter])
        )


class Scale:
    NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    SCALE_STEPS = {
        "major": [2, 2, 1, 2, 2, 2, 1],
        "natural_minor": [2, 1, 2, 2, 1, 2, 2],
        "minor_pentatonic": [3, 2, 2, 3, 2],
        "blues": [3, 2, 1, 1, 3, 2],
        "major_pentatonic": [2, 2, 3, 2, 3],
        "harmonic_minor": [2, 1, 2, 2, 1, 3, 1],
        "melodic_minor": [2, 1, 2, 2, 2, 2, 1],
        "ionian": [2, 2, 1, 2, 2, 2, 1],
        "dorian": [2, 1, 2, 2, 2, 1, 2],
        "phrygian": [1, 2, 2, 2, 1, 2, 2],
        "lydian": [2, 2, 2, 1, 2, 2, 1],
        "mixolydian": [2, 2, 1, 2, 2, 1, 2],
    }

    def __init__(self, root, scale_type):
        self.scale_notes = self.build_scale(root, scale_type)

    def build_scale(self, root, scale_type):
        root_index = self.NOTES.index(root)
        scale_notes = [
            self.NOTES[
                (root_index + sum(self.SCALE_STEPS[scale_type][:i])) % len(self.NOTES)
            ]
            for i in range(len(self.SCALE_STEPS[scale_type]))
        ]
        return scale_notes

    def get_chord_notes(self, chord_degree, chord_type):
        chord_root = self.scale_notes[chord_degree - 1]
        if chord_type == "major":
            chord_intervals = [4, 3, 5]
        elif chord_type == "minor":
            chord_intervals = [3, 4, 5]
        elif chord_type == "dominant":
            chord_intervals = [4, 3, 3, 2]
        else:
            return []

        chord_notes = [chord_root]
        current_note_index = self.NOTES.index(chord_root)
        for interval in chord_intervals:
            current_note_index = (current_note_index + interval) % len(self.NOTES)
            chord_notes.append(self.NOTES[current_note_index])

        return chord_notes


class Music:
    def __init__(self, root, scale_type, meter, total_beats, song_structure):
        self.root = root
        self.scale_type = scale_type
        self.meter = meter
        self.total_beats = total_beats
        self.song_structure = song_structure
        self.scale = Scale(root, scale_type)
        self.mid = mido.MidiFile()
        self.track = mido.MidiTrack()
        self.mid.tracks.append(self.track)
        self.CHORD_PROGRESSIONS = [[1, 4, 5, 1], [2, 5, 1, 1], [1, 6, 2, 5]]

        self.harmony_track = mido.MidiTrack()  # Add a harmony track
        self.mid.tracks.append(self.harmony_track)

    def generate_voice_leading(self, current_chord, next_chord):
        voice_leading = []

        for note in current_chord:
            # Get the note in the next chord that is closest to the current note
            closest_note = min(
                next_chord,
                key=lambda x: abs(MusicNote.to_midi(x) - MusicNote.to_midi(note)),
            )
            voice_leading.append(closest_note)

        return voice_leading

    def generate_section(self, section_length, section_type):
        notes = []
        current_chord = None

        # Select a chord progression for this section
        chord_progression = random.choice(self.CHORD_PROGRESSIONS)
        if section_type == "verse":
            chord_progression = [1, 4, 5, 1]  # just an example, modify as needed
        elif section_type == "chorus":
            chord_progression = [1, 5, 6, 4]  # just an example, modify as needed
        elif section_type == "bridge":
            chord_progression = [2, 5, 1, 6]  # just an example, modify as needed
        for beat in range(1, section_length + 1):
            rhythm = RhythmPatterns.get_rhythm(self.meter, beat)

            if beat % self.meter == 1:  # New chord on each downbeat
                next_chord = self.scale.get_chord_notes(
                    chord_progression[beat // self.meter % len(chord_progression)],
                    "major",
                )

                if current_chord:
                    # Use voice leading to transition from the current chord to the next
                    next_chord = self.generate_voice_leading(current_chord, next_chord)

                current_chord = next_chord

            note = random.choice(current_chord) + "4"  # Append octave to note
            midi_note = MusicNote.to_midi(note)
            if midi_note:
                notes.append(
                    mido.Message("note_on", note=midi_note, velocity=100, time=0)
                )
                notes.append(
                    mido.Message("note_off", note=midi_note, velocity=100, time=rhythm)
                )

        return notes

    def generate_harmony_section(self, section_length, section_type):
        notes = []
        current_chord = None

        # Select a chord progression for this section
        chord_progression = random.choice(self.CHORD_PROGRESSIONS)
        if section_type == "verse":
            chord_progression = [1, 4, 5, 1]  # just an example, modify as needed
        elif section_type == "chorus":
            chord_progression = [1, 5, 6, 4]  # just an example, modify as needed
        elif section_type == "bridge":
            chord_progression = [2, 5, 1, 6]  # just an example, modify as needed
        for beat in range(1, section_length + 1):
            rhythm = RhythmPatterns.get_rhythm(self.meter, beat)

            if beat % self.meter == 1:
                next_chord = self.scale.get_chord_notes(
                    chord_progression[beat // self.meter % len(chord_progression)],
                    "major",
                )

                if current_chord:
                    # Use voice leading to transition from the current chord to the next
                    next_chord = self.generate_voice_leading(current_chord, next_chord)

                current_chord = next_chord

            note = random.choice(current_chord) + "3"  # Append octave to note
            midi_note = MusicNote.to_midi(note)
            if midi_note:
                notes.append(
                    mido.Message("note_on", note=midi_note, velocity=100, time=0)
                )
                notes.append(
                    mido.Message("note_off", note=midi_note, velocity=100, time=rhythm)
                )

        return notes

    def generate_song(self):
        song = []
        harmony = []
        for section_type in self.song_structure:
            section_length = self.total_beats // len(self.song_structure)
            section = self.generate_section(section_length, section_type)
            harmony_section = self.generate_harmony_section(
                section_length, section_type
            )
            song.append(section)
            harmony.append(harmony_section)
        return song, harmony

    def generate_music(self):
        song, harmony = self.generate_song()
        for section in song:
            for note in section:
                self.track.append(note)
        for section in harmony:
            for note in section:
                self.harmony_track.append(note)
        return self.mid


def main():
    parser = argparse.ArgumentParser(
        description="Generate a melody based on a root note, scale, meter, number of beats, and song structure."
    )
    parser.add_argument(
        "--root", type=str, default="C", help="The root note of the melody."
    )
    parser.add_argument(
        "--scale", type=str, default="major", help="The scale to use for the melody."
    )
    parser.add_argument(
        "--meter",
        type=int,
        choices=[3, 4, 8],
        default=4,
        help="The meter to use for the melody.",
    )
    parser.add_argument(
        "--beats",
        type=int,
        default=16,
        help="The total number of beats in the song.",
    )
    parser.add_argument(
        "--song_structure",
        type=str,
        nargs="+",
        default=["verse", "chorus", "verse", "chorus"],
        help=textwrap.dedent(
            """\
                The structure of the song, given as a sequence of section types
                (e.g., 'verse chorus verse chorus bridge chorus').
            """
        ),
    )
    parser.add_argument(
        "--output", type=str, default="out", help="output filename without extension."
    )
    args = parser.parse_args()

    if os.path.exists(f"{args.output}.mid"):
        raise FileExistsError(f"{args.output}.mid")

    music = Music(args.root, args.scale, args.meter, args.beats, args.song_structure)
    midi = music.generate_music()
    midi.save(f"{args.output}.mid")


if __name__ == "__main__":
    main()
