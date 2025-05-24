# --- Start of gpmcast_config.py ---
from dataclasses import dataclass
import pandas as pd
import json

@dataclass
class NowcastConfig:
    """
    Configuration for the nowcasting system.
    Attributes:
        variable_info (dict): Metadata for variables (unit, SA, transformations).
        release_calendar (pd.DataFrame): Release dates for each variable/month.
        raw_monthly_path (str): Path to raw monthly data.
        raw_gdp_path (str): Path to quarterly GDP data.
    """
    variable_info: dict
    release_calendar: pd.DataFrame
    raw_monthly_path: str
    raw_gdp_path: str

    @classmethod
    def from_json(cls, config_path: str):
        """Load configuration from a JSON file."""
        with open(config_path, 'r') as f:
            config = json.load(f)
        return cls(
            variable_info=config["variable_info"],
            release_calendar=pd.DataFrame(config["release_calendar"]),
            raw_monthly_path=config["raw_monthly_path"],
            raw_gdp_path=config["raw_gdp_path"]
        )

    @classmethod
    def from_paths(cls, raw_monthly_path: str, raw_gdp_path: str, variable_info: dict, release_calendar: pd.DataFrame):
        """Initialize configuration directly from file paths."""
        return cls(
            variable_info=variable_info,
            release_calendar=release_calendar,
            raw_monthly_path=raw_monthly_path,
            raw_gdp_path=raw_gdp_path
        )
# --- End of gpmcast_config.py ---