import Foundation
import Testing
@testable import ClipboardModule

/// One text and what the detector should say about it; `language` nil only asks for "some code".
nonisolated struct CodeSample: Sendable, CustomTestStringConvertible {
    let name: String
    let text: String
    var language: CodeLanguage?

    var testDescription: String { name }

    init(_ name: String, _ text: String, _ language: CodeLanguage? = nil) {
        self.name = name
        self.text = text
        self.language = language
    }
}

nonisolated enum CodeSamples {
    static let code: [CodeSample] = [
        CodeSample("swift view", """
        import SwiftUI

        struct ContentView: View {
            @State private var count = 0

            var body: some View {
                Button("Tap \\(count)") { count += 1 }
            }
        }
        """, .swift),
        CodeSample("swift guard", """
        guard let url = URL(string: text) else { return nil }
        let data = try await session.data(from: url)
        """, .swift),
        CodeSample("swift closure", "let items = names.map { $0.uppercased() }"),
        CodeSample("swift enum", """
        enum Direction: String {
            case north, south
            case east = "E", west = "W"
        }
        """),
        CodeSample("javascript function", """
        function add(a, b) {
          return a + b;
        }
        console.log(add(1, 2));
        """, .javascript),
        CodeSample("javascript react", """
        const App = () => {
          const [count, setCount] = useState(0);
          return <button onClick={() => setCount(count + 1)}>{count}</button>;
        };
        export default App;
        """, .javascript),
        CodeSample("typescript interface", """
        interface User {
          id: number;
          name: string;
        }
        export const getUser = async (id: number): Promise<User> => {
          const res = await fetch(`/api/users/${id}`);
          return res.json();
        };
        """, .javascript),
        CodeSample("typescript generic", """
        type Handler<T> = (event: T) => void;
        const on = <T,>(h: Handler<T>) => h;
        """, .javascript),
        CodeSample("node require", """
        const fs = require('fs');
        module.exports = { read: (p) => fs.readFileSync(p, 'utf8') };
        """, .javascript),
        CodeSample("javascript log", #"console.log("hello");"#, .javascript),
        CodeSample("javascript arrow", "const double = (x) => x * 2;", .javascript),
        CodeSample("javascript template literal", "const msg = `Hello ${user.name}, you have ${count} new messages`;", .javascript),
        CodeSample("python function", """
        def fib(n):
            if n < 2:
                return n
            return fib(n - 1) + fib(n - 2)

        print(fib(10))
        """, .python),
        CodeSample("python class", """
        import os
        from dataclasses import dataclass

        @dataclass
        class Point:
            x: int
            y: int

            def dist(self):
                return (self.x ** 2 + self.y ** 2) ** 0.5
        """, .python),
        CodeSample("python main", """
        if __name__ == "__main__":
            main()
        """, .python),
        CodeSample("python try", """
        try:
            value = int(text)
        except ValueError:
            value = 0
        """, .python),
        CodeSample("go main", """
        package main

        import "fmt"

        func main() {
        \tfmt.Println("hello")
        }
        """, .go),
        CodeSample("go error", """
        resp, err := http.Get(url)
        if err != nil {
        \treturn err
        }
        defer resp.Body.Close()
        """, .go),
        CodeSample("go struct", """
        type User struct {
        \tID   int    `json:"id"`
        \tName string `json:"name"`
        }
        """, .go),
        CodeSample("rust main", """
        use std::collections::HashMap;

        fn main() {
            let mut map: HashMap<String, i32> = HashMap::new();
            map.insert("a".to_string(), 1);
            println!("{:?}", map);
        }
        """, .rust),
        CodeSample("rust impl", """
        impl Shape for Circle {
            fn area(&self) -> f64 {
                std::f64::consts::PI * self.r * self.r
            }
        }
        """, .rust),
        CodeSample("rust match", """
        match value {
            Some(x) => println!("{}", x),
            None => {}
        }
        """, .rust),
        CodeSample("java class", """
        public class Main {
            public static void main(String[] args) {
                System.out.println("Hello");
            }
        }
        """, .java),
        CodeSample("java annotation", """
        @Override
        public String toString() {
            return "User{" + name + "}";
        }
        """, .java),
        CodeSample("kotlin", """
        data class User(val id: Int, val name: String)

        fun main() {
            val users = listOf(User(1, "An"))
            println(users)
        }
        """, .java),
        CodeSample("c main", """
        #include <stdio.h>

        int main(void) {
            printf("hello\\n");
            return 0;
        }
        """, .c),
        CodeSample("c++ main", """
        #include <iostream>
        #include <vector>

        int main() {
            std::vector<int> v{1, 2, 3};
            for (auto x : v) std::cout << x << "\\n";
        }
        """, .c),
        CodeSample("objective-c interface", """
        @interface Foo : NSObject
        @property (nonatomic, strong) NSString *name;
        - (void)bar;
        @end
        """, .c),
        CodeSample("c macro", "#define MAX(a, b) ((a) > (b) ? (a) : (b))", .c),
        CodeSample("c# program", """
        using System;

        namespace Demo
        {
            public class Program
            {
                public static void Main()
                {
                    Console.WriteLine("Hello");
                }
            }
        }
        """, .csharp),
        CodeSample("c# members", """
        public string Name { get; set; }
        private readonly List<int> _items = new List<int>();
        """, .csharp),
        CodeSample("ruby class", """
        class Greeter
          def initialize(name)
            @name = name
          end

          def hello
            puts "Hello, #{@name}"
          end
        end
        """, .ruby),
        CodeSample("ruby block", """
        [1, 2, 3].each do |n|
          puts n
        end
        """, .ruby),
        CodeSample("php class", """
        <?php
        namespace App;

        class User {
            public function name() {
                return $this->name;
            }
        }
        """, .php),
        CodeSample("php echo", #"<?php echo "Hello"; ?>"#, .php),
        CodeSample("sql select", "SELECT id, name FROM users WHERE age > 18 ORDER BY name;", .sql),
        CodeSample("sql lowercase", "select name, age from users where age > 18 limit 10", .sql),
        CodeSample("sql insert", "INSERT INTO users (name, age) VALUES ('An', 20);", .sql),
        CodeSample("sql create", """
        CREATE TABLE users (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL
        );
        """, .sql),
        CodeSample("sql update", "UPDATE users SET name = 'Bình' WHERE id = 3;", .sql),
        CodeSample("shell script", """
        #!/bin/bash
        set -e
        for f in *.txt; do
          echo "$f"
        done
        """, .shell),
        CodeSample("shell commit", #"git commit -m "fix: crash on launch""#, .shell),
        CodeSample("shell pipe", "cat access.log | grep 404 | wc -l", .shell),
        CodeSample("shell prompt", "$ npm install --save-dev typescript", .shell),
        CodeSample("shell brew", "brew install ripgrep && rg --version", .shell),
        CodeSample("shell ls", #"ls -la ~/Library/Application\ Support"#, .shell),
        CodeSample("json object", #"{"name": "An", "age": 20, "tags": ["a", "b"]}"#, .json),
        CodeSample("json pretty", """
        {
          "id": 1,
          "items": [
            {"sku": "A1", "qty": 2},
            {"sku": "B2", "qty": 1}
          ],
          "active": true,
          "note": null
        }
        """, .json),
        CodeSample("json array", #"[{"a": 1}, {"a": 2}]"#, .json),
        CodeSample("yaml compose", """
        version: "3"
        services:
          web:
            image: nginx:latest
            ports:
              - "80:80"
        """, .yaml),
        CodeSample("yaml kubernetes", """
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: web
        spec:
          replicas: 3
        """, .yaml),
        CodeSample("yaml workflow", """
        name: CI
        on: [push]
        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - run: make test
        """, .yaml),
        CodeSample("xml document", """
        <?xml version="1.0" encoding="UTF-8"?>
        <note>
          <to>An</to>
          <body>Hi</body>
        </note>
        """, .xml),
        CodeSample("html page", """
        <!DOCTYPE html>
        <html>
          <body>
            <h1 class="title">Hello</h1>
          </body>
        </html>
        """, .xml),
        CodeSample("html fragment", #"<div class="card"><p>Xin chào</p></div>"#, .xml),
        CodeSample("css rule", """
        .card {
          display: flex;
          padding: 8px 12px;
          color: #333;
        }
        """, .css),
        CodeSample("css media query", """
        @media (max-width: 600px) {
          body { margin: 0; }
        }
        """, .css),
        CodeSample("css declarations", "color: red; background: #fff; margin: 0 auto;", .css),
        CodeSample("python print", #"print("Xin chào")"#),
        CodeSample("function call", "foo(1, 2)"),
        CodeSample("python route", """
        @app.route("/")
        def index():
            return "ok"
        """, .python),
        CodeSample("npm command", "npm run build", .shell),
        CodeSample("docker command", "docker run -d -p 80:80 nginx", .shell),
        CodeSample("shell and", "cd ~/Projects && ls", .shell),
        CodeSample("shell function", """
        deploy() {
          git pull && make build
        }
        """, .shell),
        CodeSample("minified css", "a{color:red;margin:0}", .css),
        CodeSample("json with vietnamese", #"{"tên": "Bình", "tuổi": 20}"#, .json),
        CodeSample("markdown document", """
        # Title

        - item one
        - item two

        Some **bold** text and a [link](https://example.com).
        """, .markdown),
        CodeSample("markdown fence", """
        Run it:

        ```bash
        make test
        ```
        """, .markdown),
    ]

    static let prose: [CodeSample] = [
        CodeSample("vietnamese sentence", "Hôm nay trời đẹp quá, mình đi dạo công viên nhé."),
        CodeSample("vietnamese letter", """
        Kính gửi anh Nam,

        Em xin gửi lại báo cáo tuần này. Nếu có gì cần chỉnh sửa, anh cứ nhắn em nhé (em online đến 6h chiều).

        Trân trọng,
        Hương
        """),
        CodeSample("vietnamese punctuation", "Giá: 1.500.000đ (đã gồm VAT); giao hàng trong 2–3 ngày!"),
        CodeSample("vietnamese to-do list", """
        Việc cần làm:
        - Mua sữa
        - Gọi cho mẹ
        - Nộp bài tập
        """),
        CodeSample("numbered steps", """
        1. Mở ứng dụng
        2. Chọn Cài đặt
        3. Bật thông báo
        """),
        CodeSample("vietnamese poem", """
        Trăng sáng soi đường làng,
        Gió thổi qua đồng xanh;
        Em ngồi bên cửa sổ,
        Nhớ mùa hè năm xưa.
        """),
        CodeSample("vietnamese meeting notes", """
        Họp lúc 9h: phòng A; mang theo laptop.
        Chủ đề: kế hoạch Q4 (ngân sách, nhân sự, rủi ro).
        """),
        CodeSample("vietnamese dialogue", """
        An: Chiều nay đi cà phê không?
        Bình: Được chứ, 4h nhé!
        An: Ok.
        """),
        CodeSample("vietnamese quote", "“Cảm ơn bạn,” cô ấy nói – rồi mỉm cười."),
        CodeSample("vietnamese exclamation", "Wow!!! Thật không thể tin được???"),
        CodeSample("vietnamese arrow", "Từ A -> B mất khoảng 15 phút đi bộ."),
        CodeSample("vietnamese sum", "Tổng cộng là 5 + 3 = 8 đồng."),
        CodeSample("vietnamese address", "123 Nguyễn Huệ, Quận 1, TP. Hồ Chí Minh"),
        CodeSample("vietnamese heading", "Báo cáo doanh thu quý 3 - 2025"),
        CodeSample("vietnamese date", "Thứ Hai, 12/05/2025 lúc 14:30"),
        CodeSample("vietnamese semicolons", "Mua rau; mua thịt; mua cá;"),
        CodeSample("vietnamese citation", "[1] Nguyễn Văn A, Lịch sử Việt Nam, NXB Giáo dục, 2010."),
        CodeSample("vietnamese braces", "{Hà Nội}"),
        CodeSample("vietnamese paragraph", """
        Mùa thu Hà Nội đẹp lắm, nhất là lúc chiều tà. Cả phố ngập trong màu vàng của lá, và hương hoa sữa
        thoang thoảng khắp các con ngõ nhỏ. Mình hay đi bộ quanh hồ, mua một cốc trà nóng (không đường),
        rồi ngồi nhìn người qua lại; thế là đủ vui cho cả ngày!
        """),
        CodeSample("greeting", "Xin chào"),
        CodeSample("english sentence", "The quick brown fox jumps over the lazy dog. It was a sunny day, and everyone was happy!"),
        CodeSample("english quote", #""I think, therefore I am," he said (quoting Descartes)."#),
        CodeSample("english shopping list", "Buy milk, eggs, and bread."),
        CodeSample("english bullets", """
        * milk
        * eggs
        * bread
        """),
        CodeSample("english instruction", "Please select an item from the list below and press OK."),
        CodeSample("lowercase select", "select all the files from the folder"),
        CodeSample("english note", """
        Note: bring ID
        Date: Monday
        """),
        CodeSample("english headline", "Breaking: markets rally as inflation cools"),
        CodeSample("url", "https://example.com/path?x=1&y=2"),
        CodeSample("url in sentence", "Xem thêm tại https://www.apple.com/vn/ nhé"),
        CodeSample("two urls", """
        https://example.com/a
        https://example.com/b?x=1&y=2
        """),
        CodeSample("email", "tuyet-ky.le-minh@cyberskill.world"),
        CodeSample("email in sentence", "Liên hệ: support@example.com hoặc hotline 1900 1234."),
        CodeSample("phone number", "+84 912 345 678"),
        CodeSample("number", "1234567"),
        CodeSample("word list", "táo, cam, chuối, xoài"),
        CodeSample("mention", "@nobody xem giúp mình với"),
        CodeSample("hashtags", "#hanoi #food #travel"),
        CodeSample("unix path", "/Users/me/Documents/Báo cáo.pdf"),
        CodeSample("windows path", #"C:\Users\me\Desktop\report.docx"#),
        CodeSample("time range", "10:30 - 11:45"),
        CodeSample("token", "a8F3kLm9Qz"),
        CodeSample("chat log", """
        [10:30] An: xin chào
        [10:31] Bình: chào bạn
        """),
        CodeSample("price list", """
        Cà phê: 25.000đ
        Trà sữa: 35.000đ
        Bánh mì: 20.000đ
        """),
        CodeSample("column table", """
        Tên    Tuổi
        An     20
        Bình   22
        """),
        CodeSample("chapter list", """
        Chương 1: Mở đầu
        Chương 2: Nội dung
        Chương 3: Kết luận
        """),
        CodeSample("dash list", """
        - a
        - b
        - c
        """),
        CodeSample("number list", "1, 2, 3, 4, 5"),
        CodeSample("languages sentence", "C++ và Java là hai ngôn ngữ phổ biến."),
        CodeSample("equation question", "x = 5 nghĩa là gì?"),
        CodeSample("error message", "Error: cannot find 'foo' in scope"),
        CodeSample("lorem ipsum", "Lorem ipsum dolor sit amet, consectetur adipiscing elit."),
        CodeSample("emoji", "Cảm ơn nhiều 🙏😊"),
        CodeSample("english semicolons", "I came; I saw (briefly); I left."),
        CodeSample("markdown-looking prose", "**Lưu ý:** xem [tài liệu](https://example.com) trước khi chạy."),
    ]
}
