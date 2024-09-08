
#!/bin/bash

# Define the folders
image_folder="/Users/devnologix/Downloads/Takeout 2/Google Photos/Photos from 2021"
metadata_folder="/Users/devnologix/Downloads/Takeout 2/Google Photos/Photos from 2021"

# Function to format date
format_date() {
    echo "$1" | awk '
    BEGIN {
        month_names["Jan"] = "01";
        month_names["Feb"] = "02";
        month_names["Mar"] = "03";
        month_names["Apr"] = "04";
        month_names["May"] = "05";
        month_names["Jun"] = "06";
        month_names["Jul"] = "07";
        month_names["Aug"] = "08";
        month_names["Sep"] = "09";
        month_names["Oct"] = "10";
        month_names["Nov"] = "11";
        month_names["Dec"] = "12";
    }
    {
        split($0, a, ",");
        split(a[1], b, " ");
        month = month_names[b[1]];
        day = b[2];
        year = a[2];
        time = substr(a[3], 2, length(a[3]) - 5);
        am_pm = substr(a[3], length(a[3]), 2);
        split(time, c, ":");
        if (am_pm == "PM" && c[1] != "12") {
            c[1] += 12;
        } else if (am_pm == "AM" && c[1] == "12") {
            c[1] = "00";
        }

        # Convert time to IST (UTC+5:30)
        c[1] += 5;
        if (c[1] >= 24) {
            c[1] -= 24;
            day += 1;
        }
        if (c[1] < 10) c[1] = "0" c[1]; # Ensure two digits for hour

        c[2] += 30;
        if (c[2] >= 60) {
            c[2] -= 60;
            c[1] += 1;
            if (c[1] >= 24) {
                c[1] -= 24;
                day += 1;
            }
        }
        if (c[2] < 10) c[2] = "0" c[2]; # Ensure two digits for minutes

        printf "%s-%s-%s %s:%s:%s", year, month, day, c[1], c[2], c[3];
    }'
}

convert_to_24_hour() {
    local time12="$1"

    # Clean any extra spaces or hidden characters
    time12=$(echo "$time12" | tr -d '\r')

    # Extract time and period
    local period=${time12:9:2}
    local time=${time12% *}

    # Extract hours, minutes, and seconds
    local hours=${time:0:2}
    local minutes=${time:3:2}
    local seconds=${time:6:2}

    # Convert hours based on AM/PM
    if [ "$period" == "PM" ]; then
        if [ "$hours" -ne 12 ]; then
            hours=$((hours + 12))
        fi
    elif [ "$period" == "AM" ]; then
        if [ "$hours" -eq 12 ]; then
            hours=0
        fi
    fi

    # Format hours to be two digits
    printf -v hours "%02d" "$hours"

    # Output in 24-hour format
    echo "$hours:$minutes:$seconds"
}

# Loop through all files in the image folder
for image_file in "$image_folder"/*; do
    # Get the base filename (without extension)
    base_filename=$(basename "$image_file")
    extension="${base_filename##*.}"
    base_filename="${base_filename%.*}"

    # Define the corresponding metadata file
    metadata_file="$metadata_folder/$base_filename.jpg.json"

    # Check if the metadata file exists
    if [ -f "$metadata_file" ]; then
        echo "Processing $image_file with $metadata_file"

        # Extract metadata from JSON
        description=$(jq -r '.description' "$metadata_file")
        datetime=$(jq -r '.photoTakenTime.formatted' "$metadata_file")
        file_modify_datetime=$(jq -r '.creationTime.formatted' "$metadata_file")
        file_access_datetime=$(jq -r '.creationTime.formatted' "$metadata_file")       # Use the same or different field if applicable
        file_inode_change_datetime=$(jq -r '.creationTime.formatted' "$metadata_file") # Use the same or different field if applicable

        # Debug print
        echo "Original datetime from JSON: $datetime"
        echo "File modification datetime from JSON: $file_modify_datetime"
        echo "File access datetime from JSON: $file_access_datetime"
        echo "File inode change datetime from JSON: $file_inode_change_datetime"

        # Convert date strings to EXIF format
        datetime=$(format_date "$datetime")

        # Split into date and time parts using IFS (Internal Field Separator)
        IFS=' ' read -r date_part time_part <<< "$datetime"

        # Convert time part to 24-hour format (corrected function usage)
        converted_time=$(convert_to_24_hour "$time_part")

        # Combine date and time for EXIF format
        formatted_datetime="$date_part $converted_time"
        echo "Formatted datetime for EXIF: $formatted_datetime"

        # Apply metadata to image or video file
        if [[ "$extension" == "jpg" || "$extension" == "jpeg" || "$extension" == "mp4" ]]; then
            exiftool -ImageDescription="$description" \
                -DateTimeOriginal="$formatted_datetime" \
                -FileModifyDate="$formatted_datetime" \
                -GPSLatitude=$(jq -r '.geoData.latitude' "$metadata_file") \
                -GPSLongitude=$(jq -r '.geoData.longitude' "$metadata_file") \
                -GPSAltitude=$(jq -r '.geoData.altitude' "$metadata_file") \
                -overwrite_original "$image_file"
                
            # Confirm metadata application
            echo "Metadata applied to $image_file"
            exiftool "$image_file"
        else
            echo "Unsupported file format: $extension"
        fi

        # Delete the JSON file after applying metadata
        rm "$metadata_file"
        echo "Deleted $metadata_file"

    else
        echo "Metadata file not found for $image_file"
    fi
done

