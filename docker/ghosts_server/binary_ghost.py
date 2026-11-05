import json
import struct
from dataclasses import dataclass, field, fields

def ghost_field (xml_field, json_field = None, binary_format = None, *args, **kwargs):
    return field (
        metadata={
            "xml_field": xml_field,
            "json_field": json_field or xml_field,
            "binary_format": binary_format
        },
        *args,
        **kwargs
    )

class KeyName:
    keyNames = 	[ 	"vehicle_fire", "vehicle_secondary_fire", "vehicle_left", "vehicle_right", "steer_forward", "steer_back", "accelerate",
			"brake_reverse", "horn", "sub_mission", "handbrake", "vehicle_look_left", "vehicle_look_right", "special_control_left",
			"special_control_right", "special_control_down", "special_control_up"
		 ]


    def __init__(self, value = "vehicle_fire"):
        self.value = value

    @staticmethod
    def from_bin (data):
        return KeyName(KeyName.keyNames[struct.unpack_from ("<B", data, 0)[0]]), 1

    def to_bin(self):
        data = struct.pack('<B', self.keyNames.index(self.value))
        return data

    def to_json(self):
        return self.value

class Record:
    @classmethod
    def from_xml(cls, element):
        if cls == Record:
            cls = cls.get_class_from_type_string (element.attrib['ty'])

        init_data = {}
        for field in fields(cls):
            attrib_name = field.metadata.get("xml_field", field.name)
            init_data[field.name] = field.type(element.attrib.get(attrib_name, field.type()))
            if field.type == bool:
                init_data[field.name] = element.attrib.get(attrib_name, 'false') == 'true'
        return cls(**init_data)

    @classmethod
    def from_json(cls, element):

        if cls == Record:
            cls = cls.get_class_from_type_string (element['ty'])
        
        init_data = {}
        for field in fields(cls):
            attrib_name = field.metadata.get("json_field", field.name)
            init_data[field.name] = field.type(element.get(attrib_name, field.type()))
        return cls(**init_data)

    @classmethod
    def from_bin(cls, data : bytearray):
        offset = 0
        primitive_type_defaults = {
            int: "<I",
            float: "<f",
            bool: "<b"
        }
        init_data = {}
        for field in fields(cls):
            if field.type in primitive_type_defaults:
                struct_format = field.metadata.get("binary_format", None) or primitive_type_defaults[field.type]
                init_data[field.name] = struct.unpack_from (struct_format, data, offset)[0]
                if field.type == bool:
                    init_data[field.name] = init_data[field.name] == 1
                offset += struct.calcsize (struct_format)

            elif field.type == str:
                size, = struct.unpack_from ("<h", data, offset)
                init_data[field.name] = data[offset+2:offset+2+size].decode("utf-8")
                offset += size + 2

            else:
                init_data[field.name], size = field.type.from_bin (data[offset:])
                offset += size
        return cls(**init_data), offset
    
    def to_bin (self):
        data = bytearray()
        primitive_type_defaults = {
            int: "<I",
            float: "<f",
            bool: "<b"
        }
        for field in fields(self):
            if field.type in primitive_type_defaults:
                struct_format = field.metadata.get("binary_format", None) or primitive_type_defaults[field.type]
                data += struct.pack (struct_format, getattr(self, field.name))
            elif field.type == str:
                field_val = getattr(self, field.name)
                data += struct.pack("<h", len(field_val))
                data += field_val.encode("utf-8")
            else:
                data += getattr(self, field.name).to_bin ()
        return data

    def to_json (self):
        data = {}
        for field in fields(self):
            attrib_name = field.metadata.get("json_field", field.name)
            field_val = getattr (self, field.name)
            if hasattr(field_val, "to_json"):
                data[attrib_name] = field_val.to_json ()
            else:
                data[attrib_name] = field_val
            data["ty"] = self.get_type_string ()
        return data

    @classmethod
    def get_type_string (cls):
        for type_string, typename in TYPENAMES.items():
            if cls == typename:
                return type_string
        return ""

    @staticmethod
    def get_class_from_type_string (type_string):
        return TYPENAMES.get (type_string, None)

@dataclass
class GhostHeader(Record):
    bestTime : int = ghost_field("t", "bestTime")
    racer : str = ghost_field("r", "racer")

@dataclass
class RecordStart(Record):
    x : float
    y : float
    z : float
    rX : float
    rY : float
    rZ : float
    ticks : int = ghost_field("t")
    vehType : int = ghost_field("m")
    pedType : int = ghost_field("p")

@dataclass
class RecordSpawn(Record):
    ticks : int = ghost_field("t")

@dataclass
class RecordKey(Record):
    key : KeyName = ghost_field("k")
    state : bool = ghost_field("s")
    ticks : int = ghost_field("t")

@dataclass
class RecordVehChange(Record):
    vehType : int = ghost_field("m")
    ticks : int = ghost_field("t")

@dataclass
class RecordPosition(Record):
    x : float
    y : float
    z : float
    rX : float
    rY : float
    rZ : float
    vX : float
    vY : float
    vZ : float
    gear : bool = ghost_field("lg")
    health : float = ghost_field ("h")
    ticks : int = ghost_field("t")

@dataclass
class RecordPickup(Record):
    pickup : str = ghost_field("i")
    ticks : int = ghost_field("t")

TYPENAMES = {
    'st': RecordStart,
    'sp': RecordSpawn,
    'k': RecordKey,
    'v': RecordVehChange,
    'po': RecordPosition,
    'pi': RecordPickup
}

TYPEIDS = {
    RecordStart: 0,
    RecordSpawn: 1,
    RecordKey: 2,
    RecordVehChange: 3,
    RecordPosition: 4,
    RecordPickup: 5
}

TYPENAMES = {
    'st': RecordStart,
    'sp': RecordSpawn,
    'k': RecordKey,
    'v': RecordVehChange,
    'po': RecordPosition,
    'pi': RecordPickup
}

TYPEIDS = {
    RecordStart: 0,
    RecordSpawn: 1,
    RecordKey: 2,
    RecordVehChange: 3,
    RecordPosition: 4,
    RecordPickup: 5
}

class GhostFile:
    def __init__(self):
        self.header = GhostHeader(0, '')
        self.table = []

    @staticmethod
    def from_xml(elem):
        ghost_file = GhostFile ()
        ghost_file.header = GhostHeader.from_xml(elem.find('i'))
        for record in elem.findall('n'):
            ghost_file.table.append(Record.from_xml(record))
        return ghost_file

    @staticmethod
    def from_json(elem):
        ghost_file = GhostFile ()
        ghost_file.header = GhostHeader (int(elem["bestTime"]), elem["racer"])
        for record in elem["recording"]:
            ghost_file.table.append(Record.from_json(record))
        return ghost_file

    @staticmethod
    def from_bin(data):
        ghost_file = GhostFile()
        offset = 0

        ghost_file.header, offset = GhostHeader.from_bin (data)
        num_entries, = struct.unpack_from("<I", data, offset); offset += 4

        for _ in range(num_entries):
            entry_type_id, = struct.unpack_from("<B", data, offset); offset += 1
            entry_type = None
            for entry_type_, entry_id in TYPEIDS.items():
                if entry_id == entry_type_id:
                    entry_type = entry_type_

            if entry_type is None:
                raise RuntimeError ("Wtf")

            entry, size = entry_type.from_bin (data[offset:])
            offset += size

            ghost_file.table.append(entry)

        return ghost_file

    
    def to_bin(self):
        data = self.header.to_bin()
        data += struct.pack("<I", len(self.table))
        for record in self.table:
            data += struct.pack('<B', TYPEIDS[record.__class__])
            data += record.to_bin()
        return data

    def to_json(self):
        data = self.header.to_json ()
        data["recording"] = [x.to_json() for x in self.table]
        return data
