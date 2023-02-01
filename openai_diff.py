import openai
import subprocess
import os
import re
import time

global_api_key = ""
start_commit = "4680f5292610e4fdf0872a8daf1c69ce421405b1"
end_commit = "c28e7e68391b68339468afd8a5ee8dc9bf9156ff"
directory = "C:\MSFT\DocumentationDumpTest"
model = "text-davinci-003"
max_prompt_token_limit = 2048

def break_up_large_files(file_path):
    for root, dirs, files in os.walk(file_path):
        for file in files:
            if (not file.endswith('.diff')) or (file == os.path.basename("all_diffs.diff")):
                continue
            with open(os.path.join(file_path, file), 'r', encoding='utf-8') as f:
                contents = f.read()
                lines = contents.splitlines()
                diff_line = ""
                for line in lines:
                    if "diff --git" in line:
                        diff_line = line
                        break
                if len(lines) < 2000 or (diff_line == ""):
                    continue
                else:
                    file_parts = []
                    part = ""
                    for i, line in enumerate(lines):
                        part += diff_line
                        if line == diff_line:
                            continue
                        elif len(part) + len(line) < 2000:
                            part += line + '\n'
                        else:
                            file_parts.append(part)
                            part = line + '\n'
                    file_parts.append(part)
                    for i, part in enumerate(file_parts):
                        with open(os.path.join(root, file.split('.')[0] + '_part' + str(i) + '.diff'), 'w') as f:
                            f.write(part)

def break_up_output(result, file_path):
    output = result.stdout.decode()
    files = output.split("diff --git")
    for file in files:
        if file:
            test = file.split(' ')
            filename = os.path.basename(test[1])
            if any(filename.endswith(ext) for ext in [".md", ".py", ".yml", ".yaml", ".qls",
                                                      ".json", ".uni", ".template", ".rst", 
                                                      ".gitignore", ".gitmodules", ".inc", ".markdownlintignore",
                                                      ".dsc", ".dec", ".inf", ".png"
                                                     ]):
              continue
            savedfilename = test[1].replace('/', '-')
            file_diff = "diff --git" + file
            file_name = savedfilename + '.diff'
            with open(os.path.join(file_path, file_name), "wb") as f:
                f.write(file_diff.encode())

def delete_files_with_no_parent(directory_path):
    for file_name in os.listdir(directory_path):
        if file_name.endswith('.diff') and not file_name == os.path.basename("all_diffs.diff"):
            file_path = os.path.join(directory_path, file_name)
            with open(file_path, "rb") as f:
                file = f.read()
            lines = file.decode("utf-8").split("\n")
            for line in lines:
                if '--- /dev/null' in line:
                    os.remove(file_path)
                    break

def clear_directory(directory):
    files = os.listdir(directory)
    for file in files:
        file_path = os.path.join(directory, file)
        if os.path.isfile(file_path):
            os.remove(file_path)

def get_diffs_output():
    return subprocess.run(["git", "diff", "--diff-filter=AM", "-U0", "--no-prefix", start_commit + ".." + end_commit], stdout=subprocess.PIPE)

def break_up_files(file_path, max_token_length=1000):
    with open(file_path, 'rb') as f:
        file_contents = f.read()

    lines = file_contents.split(b'\n')

    if len(lines) > max_token_length:
        first_four_lines = lines[:4]
        remaining_lines = lines[4:]

        file_number = 1
        current_line_index = 0
        current_file_contents = b''

        for line in remaining_lines:
            current_file_contents += line + b'\n'

            if current_line_index % max_token_length == 0:
                root, ext = os.path.splitext(file_path)
                new_file_path = root + '_' + str(file_number) + ext
                with open(new_file_path, 'wb') as f:
                    for line in first_four_lines:
                        f.write(line + b'\n')
                    f.write(current_file_contents)

                file_number += 1
                current_file_contents = b''

            current_line_index += 1

        root, ext = os.path.splitext(file_path)
        new_file_path = root + '_' + str(file_number) + ext
        with open(new_file_path, 'wb') as f:
            for line in first_four_lines:
                f.write(line + b'\n')
            f.write(current_file_contents)

def wrap_text(text: str, line_length: int = 100):
    words = re.findall(r'\S+', text)
    lines = []
    line = ""
    for word in words:
        if len(line) + len(word) <= line_length:
            line += " " + word
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return "\n".join(lines)

def get_completion(prompt, file_path, api_key=global_api_key, max_tokens=2048, temperature=0.5, n=1):
    retry_count = 0
    while True:
        try:
            response = openai.Completion.create(
                api_key=api_key,
                engine="text-davinci-003",
                prompt=prompt,
                max_tokens=max_tokens,
                temperature=temperature,
                n=n,
                stream=False,
                logprobs=0,
                stop=None,
            )
            return response["choices"][0]["text"]
        except openai.APIError as e:
            retry_count += 1
            if (retry_count < 3):
                print("API Error. Waiting 60 seconds to try again...")
                time.sleep(60)
                continue
            print ("Unable to get completion for file: " + file_path)
            return "Error"
        except Exception as e:
            print ("Unable to get completion for file: " + file_path)
            return "Error"

if __name__ == "__main__":
    user_input = input("Do you want to generate the diff files? Press 'y' for yes or any other key for no: ")
    diff_cunks_path = os.path.join(os.getcwd(), "diff_chunks")
    if user_input == 'y':
        print ("Diffs will be broken up by file path of the diff and deposited in directory: " + diff_cunks_path)
        clear_directory(diff_cunks_path)
        result = get_diffs_output()
        user_input = input("Do you want to create a file containing all diffs? Press 'y' for yes or any other key for no: ")

        if user_input == 'y':
            with open(os.path.join(diff_cunks_path, "all_diffs.diff"), "wb") as f:
                f.write(result.stdout)
        break_up_output (result, diff_cunks_path)
        delete_files_with_no_parent(diff_cunks_path)
        for file_name in os.listdir(diff_cunks_path):
            if file_name == os.path.basename("all_diffs.diff"):
                continue
            break_up_files(os.path.join(diff_cunks_path, file_name))

    output_path = os.path.join(os.getcwd(), "openai_output")
    user_input = input("Provide a valid output path for the OpenAI responses. If no path is provided, the files will be dumped in " + output_path + ": ")

    if user_input:
        output_path = user_input

    print ("OpenAI responses will be deposited in directory: " + output_path)

    if not os.path.exists(output_path):
        os.makedirs(output_path)
    
    for patch_file in os.listdir(diff_cunks_path):
        if patch_file == os.path.basename("all_diffs.diff"):
            continue

        with open(os.path.join(diff_cunks_path, patch_file), "rb") as f:
            print ("Processing file: " + patch_file)
            patch = f.read().decode()
            openai_prompt = "Write a justification for this EDK II diff:\n" + patch
            generated_output = get_completion(openai_prompt, os.path.join(diff_cunks_path, patch_file))
            if (generated_output != "Error"):
                with open(os.path.join(output_path, patch_file + ".txt"), "w") as f:
                    f.write(wrap_text(generated_output).lstrip())