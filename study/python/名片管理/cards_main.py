import cards_tools
import requests
while True:
    # TODO 显示菜单
    cards_tools.show_menu()
    action_str = input("请选择希望执行的操作：")
    print("您选择的操作是%s" % action_str)
    if action_str in ["1", "2", "3"]:
        if action_str == "1":
            cards_tools.new_card()
        elif action_str == "2":
            cards_tools.show_all()
        else:
            cards_tools.search_card()
    elif action_str == "0":
        break
    else:
        print("您输入的不正确，请重新选择")

requests.put
